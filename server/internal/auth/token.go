package auth

import (
	"encoding/base64"
	"strings"
)

type StaticToken string

func (t StaticToken) Authorize(header string) bool {
	token := strings.TrimSpace(header)
	if extracted := ExtractBearerToken(header); extracted != "" {
		token = extracted
	}
	return token != "" && token == string(t)
}

func ExtractBearerToken(header string) string {
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return ""
	}
	return strings.TrimSpace(strings.TrimPrefix(header, prefix))
}

type StaticBasic struct {
	Username string
	Password string
}

func (b StaticBasic) Authorize(header string) bool {
	username, password, ok := ExtractBasicCredentials(header)
	if !ok {
		return false
	}
	return username == b.Username && password == b.Password
}

type Either struct {
	Authenticators []Authenticator
}

type Authenticator interface {
	Authorize(header string) bool
}

func (e Either) Authorize(header string) bool {
	for _, authenticator := range e.Authenticators {
		if authenticator != nil && authenticator.Authorize(header) {
			return true
		}
	}
	return false
}

func ExtractBasicCredentials(header string) (string, string, bool) {
	const prefix = "Basic "
	if !strings.HasPrefix(header, prefix) {
		return "", "", false
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(strings.TrimPrefix(header, prefix)))
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}
