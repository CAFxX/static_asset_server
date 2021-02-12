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
	hidden := map[string]struct{}{}
	for _, v := range altPath {
		for _, p := range v.Paths {
			hidden[p] = struct{}{}
		}
	}

	negotiate := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet && r.Method != http.MethodHead {
				w.WriteHeader(http.StatusMethodNotAllowed)
				return
			}
			if _, hide := hidden[r.URL.Path]; hide {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			alt, ok := altPath[r.URL.Path]
			if !ok {
				goto next
			}
			log.Printf("%#v", alt)
			if alt.Image {
				if r.URL.Query().Get("content-type") == "original" {
					goto next // bypass negotiation
				}
				w.Header().Add("Vary", "Accept")
				negotiated := negotiate(r.Header.Get("Accept"), alt.Types...)
				path, found := alt.Paths[negotiated]
				if !found {
					goto next // negotiation failed
				}
				r.URL.Path = path
				r.RequestURI = r.URL.String()
				w.Header().Set("Content-Type", negotiated)
			} else {
				if r.URL.Query().Get("content-encoding") == "original" {
					goto next // bypass negotiation
				}
				w.Header().Add("Vary", "Accept-Encoding")
				negotiated := negotiate(r.Header.Get("Accept-Encoding"), alt.Types...)
				path, found := alt.Paths[negotiated]
				if !found {
					goto next // negotiation failed
				}
				r.URL.Path = path
				r.RequestURI = r.URL.String()
				w.Header().Set("Content-Encoding", negotiated)
				w.Header().Set("Content-Type", alt.MimeType)
			}
		next:
			next.ServeHTTP(w, r)
		})
	}

	logger := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			log.Print("->", " url=", r.URL.String(), " accept=", r.Header.Get("Accept"), " accept-encoding=", r.Header.Get("Accept-Encoding"))
			wr := &responseRecorder{w, 200}
			next.ServeHTTP(wr, r)
			log.Print("<-", " url=", r.URL.String(), " status=", wr.status, " content-type=", w.Header().Get("Content-Type"), " content-encoding=", w.Header().Get("Content-Encoding"), " vary=", w.Header().Get("Vary"))
		})
	}

	log.Fatal(http.ListenAndServe(":8080", logger(negotiate(http.FileServer(http.Dir(os.Args[2]))))))
}

type responseRecorder struct {
	http.ResponseWriter
	status int
}

func (wr *responseRecorder) WriteHeader(s int) {
	if wr.status == 0 {
		wr.status = s
	}
	wr.ResponseWriter.WriteHeader(s)
}

func negotiate(header string, acceptables ...string) string {
	h := accept.Parse(header)
	for _, acceptable := range acceptables {
		if h.Accepts(acceptable) {
			return acceptable
		}
	}
	return ""
}
