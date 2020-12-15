module github.com/rancher/k3s-upgrade

go 1.15

require (
	//github.com/docker/libcontainer v2.2.1+incompatible
	github.com/imdario/mergo v0.3.11 // indirect
	github.com/mitchellh/go-ps v1.0.0
	github.com/opencontainers/selinux v1.8.0
	github.com/sirupsen/logrus v1.7.0
	github.com/urfave/cli v1.22.2
	golang.org/x/time v0.0.0-20201208040808-7e3f01d25324 // indirect
	gopkg.in/yaml.v2 v2.3.0
	k8s.io/apimachinery v0.19.0
	k8s.io/client-go v0.19.0
	k8s.io/utils v0.0.0-20201110183641-67b214c5f920 // indirect
)
