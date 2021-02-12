package main

import (
	"encoding/json"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	accept "github.com/timewasted/go-accept-headers"
)

func main() {
	altPath := make(map[string]struct {
		Image    bool              `json:"image"`
		ETag     string            `json:"etag"`
		MimeType string            `json:"mime_type"`
		Types    []string          `json:"types"`
		Paths    map[string]string `json:"paths"`
	})
	buf, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	err = json.Unmarshal(buf, &altPath)
	if err != nil {
		log.Fatal(err)
	}

	negotiate := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			alt, ok := altPath[r.URL.Path]
			if !ok {
				goto next
			}
			if r.Method != http.MethodGet && r.Method != http.MethodHead {
				goto next
			}
			if alt.Image {
				if r.URL.Query().Get("content-type") != "negotiate" {
					goto next
				}
				w.Header().Add("Vary", "Accept")
				negotiated, err := accept.Negotiate(r.Header.Get("Accept"), alt.Types...)
				if err != nil {
					goto next
				}
				path, found := alt.Paths[negotiated]
				if !found {
					goto next // should never happen
				}
				r.URL.Path = path
				r.RequestURI = r.URL.String()
				w.Header().Set("Content-Type", negotiated)
				goto next
			} else {
				if r.URL.Query().Get("content-encoding") == "original" {
					goto next
				}
				w.Header().Add("Vary", "Accept-Encoding")
				negotiated, err := accept.Negotiate(r.Header.Get("Accept-Encoding"), alt.Types...)
				if err != nil {
					goto next
				}
				path, found := alt.Paths[negotiated]
				if !found {
					goto next // should never happen
				}
				r.URL.Path = path
				r.RequestURI = r.URL.String()
				w.Header().Set("Content-Encoding", negotiated)
				w.Header().Set("Content-Type", alt.MimeType)
				goto next
			}
		next:
			next.ServeHTTP(w, r)
		})
	}

	log.Fatal(http.ListenAndServe(":8080", negotiate(http.FileServer(http.Dir(os.Args[2])))))
}
