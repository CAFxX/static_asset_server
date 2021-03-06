package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	if len(os.Args) != 2 && len(os.Args) != 8 {
		log.Print("wrong number of arguments")
		return
	}

	db, err := sql.Open("sqlite3", os.Args[1])
	if err != nil {
		log.Print(err)
		return
	}
	defer db.Close()

	_, err = db.Exec("CREATE TABLE IF NOT EXISTS alt_path (path STRING, altpath STRING UNIQUE, image BOOL, filetype STRING, size INT, mimetype STRING)")
	if err != nil {
		log.Print(err)
		return
	}
	_, err = db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS path_filetype ON alt_path(path, filetype)")
	if err != nil {
		log.Print(err)
		return
	}

	if len(os.Args) == 8 {
		_, err = db.Exec("INSERT INTO alt_path (path, altpath, image, filetype, size, mimetype) VALUES (?, ?, ?, ?, ?, ?)", os.Args[2], os.Args[3], os.Args[4], os.Args[5], os.Args[6], os.Args[7])
		if err != nil {
			log.Print(err)
		}
		return
	}

	rows, err := db.Query("SELECT path, altpath, image, filetype, mimetype FROM alt_path ORDER BY size ASC")
	if err != nil {
		log.Print(err)
		return
	}
	res := make(map[string]struct {
		Types    []string          `json:"types"`
		Paths    map[string]string `json:"paths"`
		Image    bool              `json:"image"`
		MimeType string            `json:"mime_type"`
	})
	for rows.Next() {
		var path, altpath, filetype, mimetype string
		var image bool
		err = rows.Scan(&path, &altpath, &image, &filetype, &mimetype)
		if err != nil {
			log.Fatal(err)
		}
		e, exists := res[path]
		if !exists {
			e.Paths = map[string]string{}
			e.Image = image
			e.MimeType = mimetype
		} else if e.Image != image {
			log.Print("path compressed as both image and generic")
			return
		} else if e.MimeType != mimetype {
			log.Printf("inconsistent mimetype: %q != %q", e.MimeType, mimetype)
			return
		}
		e.Types = append(e.Types, filetype) // relies on `ORDER BY size ASC`
		e.Paths[filetype] = altpath
		res[path] = e
	}
	out, err := json.Marshal(res)
	if err != nil {
		log.Print(err)
		return
	}
	os.Stdout.Write(out)
}
