// Copyright 2023 Ronan Le Meillat.
// secret2sshkey is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// autocert is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this software.  If not, see <https://www.gnu.org/licenses/agpl-3.0.html>.

package main

import (
	"context"
	"flag"
	"fmt"
	"io/ioutil"
	"os"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

// create secret with
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/path/to/.ssh/id_rsa --from-file=ssh-publickey=/path/to/.ssh/id_rsa.pub --from-literal=ssh-key-type=rsa
// or
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/Users/rlemeill/.ssh/id_ecdsa --from-file=ssh-publickey=/Users/rlemeill/.ssh/id_ecdsa.pub --from-literal=ssh-key-type=ecdsa

func getCurrentContext() string {
	content, err := ioutil.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return "default"
	}
	return string(content)
}

func save(content string, file string) error {
	f, err := os.Create(file)
	if err == nil {
		f.WriteString(content)
		f.Close()
	}
	return err
}

func main() {
	var SSH_DIR = ""
	var help = flag.Bool("help", false, "Show help")
	var secretName string
	flag.StringVar(&SSH_DIR, "ssh-dir", os.Getenv("SSH_DIR"), "Directory where the keys are stored - must exists")
	flag.StringVar(&secretName, "secret", os.Getenv("SSH_SECRET"), "Kubernetes name of the secret hosting ssh-privatekey and ssh-publickey (must be in the same namespace)")
	// Parse the flags
	flag.Parse()

	// Usage Demo
	if *help {
		flag.Usage()
		os.Exit(0)
	}
	currentNamespace := getCurrentContext()

	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}

	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	context := context.TODO()

	secret, err := clientset.CoreV1().Secrets(currentNamespace).Get(
		context, secretName, metav1.GetOptions{})
	if err != nil {
		panic(err.Error())
	}

	sshPrivateKey := string(secret.Data["ssh-privatekey"])
	sshPublicKey := string(secret.Data["ssh-publickey"])
	sshKeyType := string(secret.Data["ssh-key-type"])

	// fmt.Println(sshKeyType)
	// fmt.Println(sshPrivateKey)
	// fmt.Println(sshPublicKey)

	sshPrivateKeyFile := fmt.Sprintf("%s/id_%s", SSH_DIR, sshKeyType)
	sshPublicKeyFile := fmt.Sprintf("%s/id_%s.pub", SSH_DIR, sshKeyType)

	// save key
	err = save(sshPrivateKey, sshPrivateKeyFile)
	if err != nil {
		panic(err)
	}

	err = save(sshPublicKey, sshPublicKeyFile)
	if err != nil {
		panic(err)
	}
	fmt.Printf("secret2sshkey sshKeyType=%s sshPrivateKeyFile=%s sshPublicKeyFile=%s\n", sshKeyType, sshPrivateKeyFile, sshPublicKeyFile)
}
