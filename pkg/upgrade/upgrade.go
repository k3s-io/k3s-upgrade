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
		if strings.HasSuffix(proc.Executable(), "k3s") {
			if strings.Contains(proc.Executable(), "init") || strings.Contains(proc.Executable(), "channelserver") {
				continue
			}
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
	if fileExists(string(binPath)) {
		return string(binPath), nil
	}
	return "", fmt.Errorf(" failed to fetch the k3s binary path from process %d", pid)
}

func TermProcess(pid int) error {
	proc, err := os.FindProcess(pid)
	if err != nil {
		fmt.Errorf(" process is not found")
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
		yaml.Unmarshal(fileContent, secret)
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
	if fileExists(hostPath) {
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
	}

	for entry := range preserved {
		config[entry] = preserved[entry]
	}
	content, err := yaml.Marshal(config)
	if err != nil {
		return err
	}
	return ioutil.WriteFile(hostPath, content, 0755)
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
	fullBinPath, err := GetBinPath(pid)
	if err != nil {
		return err
	}
	if !fileExists(newBinaryPath) {
		return fmt.Errorf("the new binary doesnt exist")
	}
	file, err := filepath.Abs(fullBinPath)
	if err != nil {
		return err
	}
	con, err := selinux.FileLabel(file)
	if err != nil {
		return err
	}
	//	con, err := selinux.Getfilecon(fullBinPath)
	err = os.Rename(fullBinPath, newBinaryPath)
	if err != nil {
		return err
	}
	if con != "" {
		selinux.Chcon(fullBinPath, con, true)
		//selinux.Setfilecon(fullBinPath, filecon)
	}
	return nil
}

func Prepare(masterPlan string) error {
	kubeconfig := os.Getenv("KUBECONFIG")
	conf, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return err
	}

	plansClient := dynamic.NewForConfigOrDie(conf).Resource(schema.GroupVersionResource{
		Group:    "upgrade.cattle.io",
		Version:  "v1",
		Resource: "plans",
	})
	namespace, err := ioutil.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return err
	}
	masterplans, err := plansClient.Namespace(string(namespace)).Get(context.Background(), masterPlan, v1.GetOptions{})
	if err != nil {
		return err
	}
	applyingNodes, found, err := unstructured.NestedSlice(masterplans.Object, "status", "applying")
	if !found || err != nil {
		return err
	}
	if len(applyingNodes) == 0 {
		return nil
	}
	verifyMasterVersion(os.Getenv("SYSTEM_UPGRADE_PLAN_LATEST_VERSION"))
	return nil
}

func verifyMasterVersion(masterVersion string) error {
	kubeconfig := os.Getenv("KUBECONFIG")
	conf, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return err
	}
	nodeClient := kubernetes.NewForConfigOrDie(conf).CoreV1().Nodes()
	for {
		done := true
		masterNodes, err := nodeClient.List(context.Background(), v1.ListOptions{LabelSelector: "node-role.kubernetes.io/master"})
		if err != nil {
			return err
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
