package upgrade

import (
	"context"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/pkg/errors"

	"github.com/mitchellh/go-ps"
	"github.com/opencontainers/selinux/go-selinux"
	"github.com/rancher/k3s-upgrade/pkg/types"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v2"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func fileExists(path string) bool {
	_, err := os.Stat(path)
	if os.IsNotExist(err) {
		return false
	}
	return true
}

func GetProcessPID() (int, error) {
	processes, err := ps.Processes()
	if err != nil {
		return 0, err
	}
	for _, proc := range processes {
		fmt.Println(proc.Executable())
		if strings.Contains(proc.Executable(), "k3s") {
			if strings.Contains(proc.Executable(), "init") ||
				strings.Contains(proc.Executable(), "channelserver") ||
				strings.Contains(proc.Executable(), "upgrade") {
				continue
			}
			fmt.Println(proc.Executable(), proc.Pid())
			return proc.Pid(), nil
		}
	}
	return -1, fmt.Errorf("k3s process is not running")
}

func GetBinPath(pid int) (string, error) {
	_, err := os.FindProcess(pid)
	if err != nil {
		return "", fmt.Errorf(" process is not found")
	}
	if pid == 1 {
		return "/bin/k3s", nil
	}
	binPath, err := ioutil.ReadFile(path.Join("/host/proc", strconv.Itoa(pid), "cmdline"))
	actualPath := strings.Split(string(binPath), " ")[0] //k3s
	actualPath = strings.Split(actualPath, "\x00")[0]    //k3d
	if err == nil {
		return actualPath, nil
	}
	return "", fmt.Errorf(" failed to fetch the k3s binary path from process %d", pid)
}

func TermProcess(pid int) error {
	proc, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	return proc.Signal(syscall.SIGTERM)
}

func MatchSelector(hostPath, configPath string, preservedEntries []string) error {
	kubeconfig := os.Getenv("KUBECONFIG")
	conf, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return err
	}
	nodeClient := kubernetes.NewForConfigOrDie(conf).CoreV1().Nodes()
	hostname := os.Getenv("SYSTEM_UPGRADE_NODE_NAME")
	if hostname == "" {
		hostname, err = os.Hostname()
		if err != nil {
			return err
		}
	}
	host, err := nodeClient.Get(context.Background(), hostname, v1.GetOptions{})
	if err != nil {
		return err
	}
	hostLabels := host.GetLabels()
	secretfiles, err := ioutil.ReadDir(configPath)
	if err != nil {
		return err
	}
	var secret types.Secret
	secretfiles = sortFileByName(secretfiles)
	for _, secretFile := range secretfiles {
		fileContent, err := ioutil.ReadFile(secretFile.Name())
		if err != nil {
			return err
		}
		err = yaml.Unmarshal(fileContent, secret)
		if err != nil {
			return err
		}
		selector, err := v1.LabelSelectorAsSelector(&secret.Selector)
		if err != nil {
			return err
		}
		if selector.Matches(labels.Set(hostLabels)) {
			//check if a config file is present on the node
			return PlaceConfigFile(hostPath, secret.Config, preservedEntries)

		}
	}
	return nil
}

func PlaceConfigFile(hostPath string, config map[string]interface{}, preservedEntries []string) error {
	preserved := make(map[string]interface{})
	if _, err := os.Stat(hostPath); err != nil {
		logrus.Infof("config file exists on the host")
		filetxt, err := ioutil.ReadFile(hostPath)
		if err != nil {
			return err
		}
		hostconfig := make(map[string]interface{})
		err = yaml.Unmarshal(filetxt, hostconfig)
		if err != nil {
			return err
		}
		for _, entry := range preservedEntries {
			if hostconfig[entry] != nil {
				preserved[entry] = hostconfig[entry]
			}
		}
	} else {
		return err
	}

	for entry := range preserved {
		config[entry] = preserved[entry]
	}
	content, err := yaml.Marshal(config)
	if err != nil {
		return err
	}
	return ioutil.WriteFile(hostPath, content, 0600)
}

func sortFileByName(files []os.FileInfo) []os.FileInfo {
	sort.Slice(files, func(i, j int) bool {
		return files[i].Name() < files[j].Name()
	})
	return files
}

func ReplaceBinary() error {
	newBinaryPath := "/opt/k3s"
	pid, err := GetProcessPID()
	if err != nil {
		return err
	}
	binPath, err := GetBinPath(pid)
	if err != nil {
		return errors.Wrap(err, "1")
	}
	if _, err = os.Stat(newBinaryPath); err != nil {
		return errors.Wrap(err, "2")
	}
	fullBinPath := path.Join("/host", binPath)
	con, err := selinux.FileLabel(fullBinPath)
	if err != nil {
		con = ""
	}
	//con, err := selinux.Getfilecon(fullBinPath)
	tmpdir, err := ioutil.TempDir(filepath.Split(fullBinPath))
	if err != nil {
		return errors.Wrap(err, "7")
	}
	tmpfile, err := ioutil.TempFile(tmpdir, "tmp")
	if err != nil {
		return errors.Wrap(err, "6")
	}
	defer os.Remove(tmpdir)
	content, err := ioutil.ReadFile(newBinaryPath)
	if _, err := tmpfile.Write(content); err != nil {
		return errors.Wrap(err, "4")
	}
	orgBinInfo, err := os.Stat(fullBinPath)
	if err != nil {
		return err
	}
	fileMode := orgBinInfo.Mode()
	fmt.Println("tmp", tmpfile.Name())
	err = os.Rename(tmpfile.Name(), fullBinPath)
	if err != nil {
		return errors.Wrap(err, "5")
	}
	err = os.Chmod(fullBinPath, fileMode)
	if con != "" {
		selinux.Chcon(fullBinPath, con, true)
		//selinux.Setfilecon(fullBinPath, con)
	}
	return nil
}

func Prepare(masterPlan string) error {
	fmt.Println("in prepare container")
	kubeconfig := os.Getenv("KUBECONFIG")
	conf, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return err
	}
	fmt.Println("after kubeconfig")

	plansClient := dynamic.NewForConfigOrDie(conf).Resource(schema.GroupVersionResource{
		Group:    "upgrade.cattle.io",
		Version:  "v1",
		Resource: "plans",
	})
	namespace, err := ioutil.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return err
	}
	fmt.Println("after namespace", string(namespace))

	masterplans, err := plansClient.Namespace(string(namespace)).Get(context.Background(), masterPlan, v1.GetOptions{})
	if err != nil {
		return err
	}
	fmt.Println("after master-plan")

	applyingNodes, found, err := unstructured.NestedSlice(masterplans.Object, "status", "applying")
	if !found || err != nil {
		return err
	}
	if len(applyingNodes) == 0 {
		return nil
	}
	fmt.Println("after applying nodes")

	return verifyMasterVersion(os.Getenv("SYSTEM_UPGRADE_PLAN_LATEST_VERSION"))

}

func verifyMasterVersion(masterVersion string) error {
	kubeconfig := os.Getenv("KUBECONFIG")
	fmt.Println("after kubeconfig")
	conf, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return err
	}
	fmt.Println("after conf")

	nodeClient := kubernetes.NewForConfigOrDie(conf).CoreV1().Nodes()
	fmt.Println("after nodeclient")

	for {
		done := true
		masterNodes, err := nodeClient.List(context.Background(), v1.ListOptions{LabelSelector: "node-role.kubernetes.io/master"})
		if err != nil {
			fmt.Println("cant get master nodes")
		}
		for _, node := range masterNodes.Items {
			if node.Status.NodeInfo.KubeletVersion != masterVersion {
				time.Sleep(5 * time.Second)
				done = false
			}
		}
		if done {
			break
		}
	}
	return nil
}
