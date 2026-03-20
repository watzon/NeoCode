package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/watzon/neocode/server/internal/api"
	"github.com/watzon/neocode/server/internal/auth"
	"github.com/watzon/neocode/server/internal/core"
	"github.com/watzon/neocode/server/internal/runtime"
	"github.com/watzon/neocode/server/internal/service"
	"github.com/watzon/neocode/server/internal/store"
)

var version = "dev"

func main() {
	if shouldPrintVersion(os.Args[1:]) {
		fmt.Println(version)
		return
	}

	host, port := parseServeArgs(os.Args[1:])
	token := os.Getenv("NEOCODE_SERVER_TOKEN")
	username := os.Getenv("OPENCODE_SERVER_USERNAME")
	password := os.Getenv("OPENCODE_SERVER_PASSWORD")
	if username == "" {
		username = "opencode"
	}
	if password == "" {
		password = token
	}

	bind := os.Getenv("NEOCODE_SERVER_BIND")
	if bind == "" {
		bind = net.JoinHostPort(host, strconv.Itoa(port))
	}

	opencodeExecutable := os.Getenv("NEOCODE_OPENCODE_EXECUTABLE")
	if opencodeExecutable == "" {
		opencodeExecutable = "opencode"
	}

	var app *service.App
	manager := runtime.NewManager(opencodeExecutable, func(event core.ServerEvent) {
		if app != nil {
			app.PublishServerEvent(event)
		}
	})

	app = service.New(service.Config{
		Info: core.ServerInfo{
			Name:    "NeoCode Server",
			Version: version,
			Mode:    core.ServerModeEmbedded,
		},
		Authenticator: auth.Either{Authenticators: []auth.Authenticator{
			auth.StaticBasic{Username: username, Password: password},
			auth.StaticToken(token),
		}},
		Store:   store.NewMemoryStore(),
		Runtime: service.EchoRuntime{},
		Bridge:  service.OpenCodeBridge{Manager: manager},
		Git:     service.LocalGitProvider{},
		Files:   service.LocalFileProvider{},
	})

	handler := api.NewHandler(app)
	listener, err := net.Listen("tcp", bind)
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	log.Printf("NeoCode server listening on http://%s", listener.Addr().String())
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func shouldPrintVersion(args []string) bool {
	for _, arg := range args {
		if arg == "--version" || arg == "version" {
			return true
		}
	}
	return false
}

func parseServeArgs(args []string) (string, int) {
	host := "127.0.0.1"
	port := 39123
	if len(args) > 0 && args[0] == "serve" {
		args = args[1:]
	}
	for index := 0; index < len(args); index++ {
		switch args[index] {
		case "--hostname":
			if index+1 < len(args) {
				host = strings.TrimSpace(args[index+1])
				index++
			}
		case "--port":
			if index+1 < len(args) {
				if parsed, err := strconv.Atoi(strings.TrimSpace(args[index+1])); err == nil {
					port = parsed
				}
				index++
			}
		case "--help", "-h":
			fmt.Println("Usage: neocoded serve [--hostname HOST] [--port PORT]")
			os.Exit(0)
		}
	}
	return host, port
}
