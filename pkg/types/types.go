package types

import v1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type Secret struct {
	nodeConfigs `yaml:"nodeconfigs,omitempty"`
}
type nodeConfigs struct {
	Config   map[string]interface{} `yaml:"config,omitempty"`
	Selector v1.LabelSelector       `yaml:"selector,omitempty"`
}
