// Copyright 2023-2024 Ronan Le Meillat.
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
	"log"
	"os"
	"path/filepath"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	SSHPrivateKeyKey = "ssh-privatekey"
	SSHPublicKeyKey  = "ssh-publickey"
	SSHKeyTypeKey    = "ssh-key-type"
)

// create secret with
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/path/to/.ssh/id_rsa --from-file=ssh-publickey=/path/to/.ssh/id_rsa.pub --from-literal=ssh-key-type=rsa
// or
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/Users/rlemeill/.ssh/id_ecdsa --from-file=ssh-publickey=/Users/rlemeill/.ssh/id_ecdsa.pub --from-literal=ssh-key-type=ecdsa

func getCurrentContext() (string, error) {
	content, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return "default", err
	}
	return string(content), nil
}

func save(content string, file string) error {
	f, err := os.Create(file)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(content)
	if err != nil {
		return err
	}

	return nil
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
	if *help || SSH_DIR == "" || secretName == "" {
		flag.Usage()
		os.Exit(0)
	}

	currentNamespace, err := getCurrentContext()
	if err != nil {
		log.Fatalf("Failed to get current context: %v", err)
	}
	// creates the in-cluster config
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Panicf("Failed to get in-cluster config: %v", err)
	}

	// creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Panicf("Failed to get clientset: %v", err)
	}

	context := context.TODO()

	secret, err := clientset.CoreV1().Secrets(currentNamespace).Get(
		context, secretName, metav1.GetOptions{})
	if err != nil {
		log.Panicf("Failed to get secret: %v", err)
	}

	if secret == nil {
		log.Panicf("Secret %s not found in namespace %s", secretName, currentNamespace)
	}

	if secret.Data[SSHPrivateKeyKey] == nil {
		log.Panicf("Secret %s does not contain %s", secretName, SSHPrivateKeyKey)
	}

	if secret.Data[SSHPublicKeyKey] == nil {
		log.Panicf("Secret %s does not contain %s", secretName, SSHPublicKeyKey)
	}

	if secret.Data[SSHKeyTypeKey] == nil {
		log.Panicf("Secret %s does not contain %s", secretName, SSHKeyTypeKey)
	}

	sshPrivateKey := string(secret.Data[SSHPrivateKeyKey])
	sshPublicKey := string(secret.Data[SSHPublicKeyKey])
	sshKeyType := string(secret.Data[SSHKeyTypeKey])

	sshPrivateKeyFile := filepath.Join(SSH_DIR, fmt.Sprintf("id_%s", sshKeyType))
	sshPublicKeyFile := filepath.Join(SSH_DIR, fmt.Sprintf("id_%s.pub", sshKeyType))

	// save key
	err = save(sshPrivateKey, sshPrivateKeyFile)
	if err != nil {
		log.Fatalf("Failed to save privateKey: %v", err)
	}

	err = save(sshPublicKey, sshPublicKeyFile)
	if err != nil {
		log.Fatalf("Failed to save publicKey: %v", err)
	}

	err = os.Chmod(sshPrivateKeyFile, 0600)
	if err != nil {
		log.Fatalf("Failed to set permissions on privateKey file: %v", err)
	}

	log.Printf("secret2sshkey sshKeyType=%s sshPrivateKeyFile=%s sshPublicKeyFile=%s\n", sshKeyType, sshPrivateKeyFile, sshPublicKeyFile)
}
