package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

func uploadFiles() {
	sourceDir := os.Getenv("SOURCE_DIR")
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
		CRON_TIME := os.Getenv("TIME")

		// time should be in UTC format, e.g., "20:00" for 8 PM UTC
		if CRON_TIME == "" {
			fmt.Println("TIME environment variable not set, defaulting to 20:00 UTC")
			CRON_TIME = "20:00"
		}

		// Parse the CRON_TIME to get the hour and minute
		parts := make([]int, 2)
		_, err := fmt.Sscanf(CRON_TIME, "%d:%d", &parts[0], &parts[1])
		if err != nil {
			fmt.Printf("Invalid TIME format: %s, expected HH:MM\n", CRON_TIME)
			os.Exit(1)
		}

		// Create a time object for the next run
		now := time.Now().UTC()
		// Set the next run time to today at the specified hour and minute
		next := time.Date(now.Year(), now.Month(), now.Day(), parts[0], parts[1], 0, 0, time.UTC)
		if now.After(next) {
			// If the current time is after the next run time, set it to tomorrow
			next = next.Add(24 * time.Hour)
		}

		// CRON_TIME + 5:30 for ist
		now = time.Date(now.Year(), now.Month(), now.Day(), now.Hour(), now.Minute(), 0, 0, time.UTC).Add(5*time.Hour + 30*time.Minute)
		next = time.Date(next.Year(), next.Month(), next.Day(), next.Hour(), next.Minute(), 0, 0, time.UTC).Add(5*time.Hour + 30*time.Minute)

		// Sleep until the next run time
		fmt.Printf("Current time (IST): %v, Next run time (IST): %v\n", now, next)

		// If the current time is after the next run time, set it to tomorrow
		if now.After(next) {
			next = next.Add(24 * time.Hour)
		}
		dur := next.Sub(now)
		fmt.Printf("Sleeping for %v until next run at %v (IST)\n", dur, next)
		time.Sleep(dur)
		uploadFiles()
	}
}
