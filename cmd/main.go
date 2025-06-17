package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func uploadFiles() {
	sourceDir := os.Getenv("SOURCE_DIR")
	s3Bucket := os.Getenv("S3_BUCKET")
	var successfulUploads []string
	// Walk through all files and folders recursively
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
		// Split relPath to insert epoch before filename
		dir, file := filepath.Split(relPath)
		epoch := fmt.Sprintf("%d", info.ModTime().Unix())
		s3Key := filepath.ToSlash(filepath.Join(dir, epoch, file))
		s3Dest := fmt.Sprintf("%s/%s", strings.TrimRight(s3Bucket, "/"), s3Key)
		cmd := exec.Command("bash", "-c", fmt.Sprintf("aws s3 cp '%s' '%s'", path, s3Dest))
		fmt.Println(cmd)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		fmt.Printf("Uploading %s to %s...\n", path, s3Dest)
		err = cmd.Run()
		if err != nil {
			fmt.Printf("Failed to upload %s: %v\n", path, err)
		} else {
			fmt.Printf("Uploaded %s successfully.\n", path)
			successfulUploads = append(successfulUploads, path)
		}
		return nil
	})
	if err != nil {
		fmt.Println("Error walking the path:", err)
	}
	// // Delete files that were uploaded successfully
	// for _, file := range successfulUploads {
	// 	err := os.Remove(file)
	// 	if err != nil {
	// 		fmt.Printf("Failed to delete %s: %v\n", file, err)
	// 	} else {
	// 		fmt.Printf("Deleted %s after upload.\n", file)
	// 	}
	// }
}

func main() {
	// for {
	// 	now := time.Now().UTC()
	// 	// Manually add 5 hours 30 minutes to UTC for IST
	// 	// ist := now.Add(5*time.Hour + 30*time.Minute)
	// 	next := time.Date(now.Year(), now.Month(), now.Day(), 14, 40, 0, 0, time.UTC) //8pm ist
	// 	if now.After(next) {
	// 		next = next.Add(24 * time.Hour)
	// 	}
	// 	dur := next.Sub(now)
	// 	fmt.Printf("Sleeping for %v until next run at %v (IST)\n", dur, next)
	// 	time.Sleep(dur)
	uploadFiles()
	// }
}
