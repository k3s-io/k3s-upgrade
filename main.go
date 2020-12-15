package main

import (
	"fmt"
	"os"

	upgrade2 "github.com/rancher/k3s-upgrade/pkg/upgrade"

	"github.com/sirupsen/logrus"
	"github.com/urfave/cli"
)

var (
	Version          = "v0.0.1"
	GitCommit        = "HEAD"
	hostPath         string
	configPath       string
	preservedEntries cli.StringSlice
	masterPlan       string
)

func main() {
	app := cli.NewApp()
	app.Name = "k3s-upgrade"
	app.Commands = cli.Commands{
		cli.Command{
			Name: "prepare",
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:        "master-plan",
					EnvVar:      "MASTER_PLAN",
					Destination: &masterPlan,
				},
			},
			Action: prepare},
		cli.Command{
			Name:   "upgrade",
			Action: upgrade},
		cli.Command{
			Name:   "config",
			Action: conf,
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:        "host-path",
					EnvVar:      "HOST_PATH",
					Destination: &hostPath,
				},
				cli.StringFlag{
					Name:        "config-path",
					EnvVar:      "CONFIG_PATH",
					Destination: &configPath,
				},
				cli.StringSliceFlag{
					Name:   "preserved-entries",
					EnvVar: "PRESERVED_ENTRIES",
					Value:  &preservedEntries,
				},
			},
		},
	}
	app.Version = fmt.Sprintf("%s (%s)", Version, GitCommit)
	app.Usage = "upgrade container for k3s clusters"

	if err := app.Run(os.Args); err != nil {
		logrus.Fatal(err)
	}
}

func upgrade(c *cli.Context) error {
	pid, err := upgrade2.GetProcessPID()
	if err != nil {
		return err
	}
	err = upgrade2.ReplaceBinary()
	if err != nil {
		return err
	}
	return upgrade2.TermProcess(pid)
}

func prepare(c *cli.Context) error {
	return upgrade2.Prepare(masterPlan)
}
func conf(c *cli.Context) error {
	return upgrade2.MatchSelector(hostPath, configPath, preservedEntries)
}
