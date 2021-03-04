package main

import (
	"context"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	accept "github.com/timewasted/go-accept-headers"
	"go.uber.org/zap"
)

const (
	webrootDir  = "/webroot"
	altPathFile = "/alt_path.json"
	certFile    = "/server.crt"
	keyFile     = "/server.key"
)

func main() {
	log, _ := zap.NewProductionConfig().Build()
	log = log.Named("server")
	log.Info("starting")

	altPath := make(map[string]struct {
		Image    bool              `json:"image"`
		MimeType string            `json:"mime_type"`
		Types    []string          `json:"types"`
		Paths    map[string]string `json:"paths"`
	})
	buf, err := ioutil.ReadFile(altPathFile)
	if err != nil {
		log.Fatal("reading "+altPathFile, zap.Error(err))
	}
	err = json.Unmarshal(buf, &altPath)
	if err != nil {
		log.Fatal("parsing "+altPathFile, zap.Error(err))
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
				negotiated := negotiateAccept(r.Header.Get("Accept"), alt.Types...)
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
				negotiated := negotiateAccept(r.Header.Get("Accept-Encoding"), alt.Types...)
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
		log := log.Named("accesslog")
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if ce := log.Check(zap.InfoLevel, "request"); ce != nil {
				url, accept, acceptEncoding, start := r.URL.String(), r.Header.Get("Accept"), r.Header.Get("Accept-Encoding"), time.Now()
				wr := &responseRecorder{ResponseWriter: w}
				defer func() {
					duration := time.Since(start)
					ce.Write(
						zap.String("url", url),
						zap.String("variant", r.URL.String()),
						zap.String("accept", accept),
						zap.String("accept-encoding", acceptEncoding),
						zap.Int("status", wr.status),
						zap.String("content-type", w.Header().Get("Content-Type")),
						zap.String("content-encoding", w.Header().Get("Content-Encoding")),
						zap.String("vary", w.Header().Get("Vary")),
						zap.Int("length", wr.written),
						zap.Duration("duration", duration),
					)
				}()
				w = wr
			}
			next.ServeHTTP(w, r)
		})
	}

	fs := justFilesFilesystem{http.Dir(webrootDir)}
	server := &http.Server{
		Handler: logger(negotiate(http.FileServer(fs))),
	}
	if port := os.Getenv("PORT"); port != "" {
		server.Addr = ":" + port
	}
	go func() {
		_, err := os.Stat(certFile)
		if err != nil && os.IsNotExist(err) {
			err = server.ListenAndServe()
		} else {
			err = server.ListenAndServeTLS(certFile, keyFile)
		}
		if err == http.ErrServerClosed {
			log.Info("closed")
		} else {
			log.Fatal("ListenAndServe*", zap.Error(err))
		}
	}()
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, os.Interrupt, os.Kill, syscall.SIGTERM)
	sig := <-ch
	log.Info("received signal: shutting down gracefully", zap.String("signal", sig.String()))
	server.Shutdown(context.Background())
	log.Info("exiting")
}

type responseRecorder struct {
	http.ResponseWriter
	status  int
	written int
}

func (wr *responseRecorder) WriteHeader(s int) {
	if wr.status == 0 {
		wr.status = s
	}
	wr.ResponseWriter.WriteHeader(s)
}

func (wr *responseRecorder) Write(b []byte) (int, error) {
	if wr.status == 0 {
		wr.status = http.StatusOK
	}
	n, err := wr.ResponseWriter.Write(b)
	wr.written += n
	return n, err
}

func negotiateAccept(header string, acceptables ...string) string {
	parsedHeader := accept.Parse(header)
	ua := parsedHeader[:0]
	for _, acc := range parsedHeader {
		if acc.Type == "*" || acc.Subtype == "*" {
			// Browsers sends `image/*` or `*/*` in Accept, even though it's a lie.
			// It makes sense to not consider for content-type negotiation
			// content types that are not *explicitly* listed as acceptable,
			// even though a strict interpretation of RFC 7231 would require
			// to consider the wildcards as well.
			// https://tools.ietf.org/html/rfc7231#section-5.3.2
			// TODO: Use a browser capability database to know which types are
			// actually accepted.
			continue
		}
		ua = append(ua, acc) // filter in-place
	}
	for _, acceptable := range acceptables {
		if ua.Accepts(acceptable) {
			return acceptable
		}
	}
	return ""
}

type justFilesFilesystem struct {
	fs http.FileSystem
}

func (fs justFilesFilesystem) Open(name string) (http.File, error) {
	f, err := fs.fs.Open(name)
	if err != nil {
		return nil, err
	}

	stat, err := f.Stat()
	if err == nil && stat.IsDir() {
		f.Close()
		return nil, os.ErrNotExist
	}
	return f, err
}
