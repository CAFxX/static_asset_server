package main

import (
	"encoding/json"
	"io/ioutil"
	"net/http"
	"os"
	"time"

	accept "github.com/timewasted/go-accept-headers"
	"go.uber.org/zap"
)

func main() {
	log, _ := zap.NewProductionConfig().Build()
	log.Info("starting server")

	altPath := make(map[string]struct {
		Image    bool              `json:"image"`
		MimeType string            `json:"mime_type"`
		Types    []string          `json:"types"`
		Paths    map[string]string `json:"paths"`
	})
	buf, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		log.Fatal("reading altPath", zap.Error(err))
	}
	err = json.Unmarshal(buf, &altPath)
	if err != nil {
		log.Fatal("pasring altPath", zap.Error(err))
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
			if ce := log.Check(zap.InfoLevel, "request"); ce != nil {
				url, accept, acceptEncoding, start := r.URL.String(), r.Header.Get("Accept"), r.Header.Get("Accept-Encoding"), time.Now()
				wr := &responseRecorder{w, 0}
				defer func() {
					duration := time.Since(start)
					ce.Write(
						zap.String("url", url),
						zap.String("url_alt", r.URL.String()),
						zap.String("accept", accept),
						zap.String("acceptEncoding", acceptEncoding),
						zap.Int("status", wr.status),
						zap.String("content-type", w.Header().Get("Content-Type")),
						zap.String("content-encoding", w.Header().Get("Content-Encoding")),
						zap.String("vary", w.Header().Get("Vary")),
						zap.Duration("duration", duration),
					)
				}()
				w = wr
			}
			next.ServeHTTP(w, r)
		})
	}

	handler := logger(negotiate(http.FileServer(http.Dir(os.Args[2]))))
	log.Fatal("server", zap.Error(http.ListenAndServe(":8080", handler)))
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

func (wr *responseRecorder) Write(b []byte) (int, error) {
	if wr.status == 0 {
		wr.status = 200
	}
	return wr.ResponseWriter.Write(b)
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
