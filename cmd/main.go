package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

func uploadFiles() {
	sourceDir := "./files"
	s3Bucket := os.Getenv("S3_BUCKET")
	if s3Bucket == "" {
		fmt.Println("S3_BUCKET environment variable not set")
		os.Exit(1)
	}
	epoch := fmt.Sprintf("%d", time.Now().Unix())
	err := filepath.Walk(sourceDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			fmt.Printf("Error accessing %s: %v\n", path, err)
			return nil
		}
		if info.IsDir() {
			return nil
		}
		relPath, err := filepath.Rel(sourceDir, path)
		if err != nil {
			fmt.Printf("Error getting relative path for %s: %v\n", path, err)
			return nil
		}
		s3Dest := fmt.Sprintf("%s/%s/%s", s3Bucket, epoch, filepath.ToSlash(relPath))
		cmd := exec.Command("bash", "-c", fmt.Sprintf("aws s3 cp '%s' '%s'", path, s3Dest))
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		fmt.Printf("Uploading %s to %s...\n", path, s3Dest)
		err = cmd.Run()
		if err != nil {
			fmt.Printf("Failed to upload %s: %v\n", path, err)
		} else {
			fmt.Printf("Uploaded %s successfully.\n", path)
		}
		return nil
	})
	if err != nil {
		fmt.Println("Error walking the path:", err)
	}
}

func main() {
	for {
		now := time.Now().UTC()
		next := time.Date(now.Year(), now.Month(), now.Day(), 10, 35, 0, 0, time.UTC) //8pm ist
		if now.After(next) {
			next = next.Add(24 * time.Hour)
		}
		dur := next.Sub(now)
		fmt.Printf("Sleeping for %v until next run at %v (IST)\n", dur, next)
		time.Sleep(dur)
		uploadFiles()
	}
}
