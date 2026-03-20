package auth

import "testing"

func TestExtractBearerToken(t *testing.T) {
	tests := []struct {
		name   string
		header string
		want   string
	}{
		{name: "valid", header: "Bearer abc123", want: "abc123"},
		{name: "trimmed", header: "Bearer   abc123  ", want: "abc123"},
		{name: "missing prefix", header: "abc123", want: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ExtractBearerToken(tt.header); got != tt.want {
				t.Fatalf("got %q want %q", got, tt.want)
			}
		})
	}
}

func TestStaticTokenAuthorize(t *testing.T) {
	auth := StaticToken("secret")
	if !auth.Authorize("secret") {
		t.Fatal("expected token to authorize")
	}
	if auth.Authorize("wrong") {
		t.Fatal("expected wrong token to fail")
	}
}
