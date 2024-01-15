// secret2sshkey is a small utility to extract ssh keys from a Kubernetes secret
// create secret with
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/path/to/.ssh/id_rsa --from-file=ssh-publickey=/path/to/.ssh/id_rsa.pub --from-literal=ssh-key-type=rsa
// or
// kubectl create secret generic ssh-key-secret --from-file=ssh-privatekey=/Users/rlemeill/.ssh/id_ecdsa --from-file=ssh-publickey=/Users/rlemeill/.ssh/id_ecdsa.pub --from-literal=ssh-key-type=ecdsa

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
	"crypto/x509"
	"encoding/pem"
	"errors"
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

// isPEMCertificate checks if the certificate is a PEM encoded certificate
func isPEMCertificate(cert string) (*x509.Certificate, error) {
	block, _ := pem.Decode([]byte(cert))
	if block == nil {
		return nil, errors.New("failed to parse certificate PEM")
	}
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, err
	}
	return certificate, nil
}

// isPEMPrivateKey checks if the key is a PEM encoded private key
func isPEMPrivateKey(key string) (bool, error) {
	block, _ := pem.Decode([]byte(key))
	if block == nil {
		return false, errors.New("failed to parse key PEM")
	}
	_, err := x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		_, err = x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			_, err = x509.ParseECPrivateKey(block.Bytes)
			if err != nil {
				return false, err
			}
		}
	}
	return true, nil
}

// getCurrentContext returns the current namespace
func getCurrentContext() (string, error) {
	content, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return "default", err
	}
	return string(content), nil
}

// save saves content to file
func save(content string, file string) error {
	f, err := os.Create(file)
	if err != nil {
		return err
	}
	defer f.Close()

	// write content to file
	_, err = f.WriteString(content)
	if err != nil {
		return err
	}

	return nil
}

// main
func main() {
	var SSH_DIR = ""
	var help = flag.Bool("help", false, "Show help")
	var secretName string
	// Define the flags
	flag.StringVar(&SSH_DIR, "ssh-dir", os.Getenv("SSH_DIR"), "Directory where the keys are stored - must exists")
	flag.StringVar(&secretName, "secret", os.Getenv("SSH_SECRET"), "Kubernetes name of the secret hosting ssh-privatekey and ssh-publickey (must be in the same namespace)")
	// Parse the flags
	flag.Parse()

	// Display help
	if *help || SSH_DIR == "" || secretName == "" {
		flag.Usage()
		os.Exit(0)
	}

	// get current namespace
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

	// check if secret contains ssh-privatekey, ssh-publickey and ssh-key-type
	if secret == nil || secret.Data == nil {
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
	_, err = isPEMPrivateKey(sshPrivateKey)
	if err != nil {
		log.Fatalf("Failed to parse private key: %v", err)
	}

	sshPublicKey := string(secret.Data[SSHPublicKeyKey])
	_, err = isPEMCertificate(sshPublicKey)
	if err != nil {
		log.Fatalf("Failed to parse public key: %v", err)
	}

	sshKeyType := string(secret.Data[SSHKeyTypeKey])
	if sshKeyType != "rsa" && sshKeyType != "ecdsa" && sshKeyType != "ed25519" && sshKeyType != "dsa" {
		log.Fatalf("Invalid ssh key type: %s key type must be rsa, ecdsa, dsa, ed25519", sshKeyType)
	}

	sshPrivateKeyFile := filepath.Join(SSH_DIR, fmt.Sprintf("id_%s", sshKeyType))
	sshPublicKeyFile := filepath.Join(SSH_DIR, fmt.Sprintf("id_%s.pub", sshKeyType))

	// save private key
	err = save(sshPrivateKey, sshPrivateKeyFile)
	if err != nil {
		log.Fatalf("Failed to save privateKey: %v", err)
	}

	// save public key
	err = save(sshPublicKey, sshPublicKeyFile)
	if err != nil {
		log.Fatalf("Failed to save publicKey: %v", err)
	}

	// set permissions on private key
	err = os.Chmod(sshPrivateKeyFile, 0600)
	if err != nil {
		log.Fatalf("Failed to set permissions on privateKey file: %v", err)
	}

	log.Printf("secret2sshkey sshKeyType=%s sshPrivateKeyFile=%s sshPublicKeyFile=%s\n", sshKeyType, sshPrivateKeyFile, sshPublicKeyFile)
}
