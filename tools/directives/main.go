package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
)

var contexts = map[string][]string{
	"ngxMainConf":       {"main"},
	"ngxEventConf":      {"events"},
	"ngxMailMainConf":   {"mail"},
	"ngxMailSrvConf":    {"mail_server"},
	"ngxStreamMainConf": {"stream"},
	"ngxStreamSrvConf":  {"stream_server"},
	"ngxStreamUpsConf":  {"stream_upstream"},
	"ngxHTTPMainConf":   {"http"},
	"ngxHTTPSrvConf":    {"server"},
	"ngxHTTPLocConf":    {"location"},
	"ngxHTTPUpsConf":    {"upstream"},
	"ngxHTTPSifConf":    {"server_if"},
	"ngxHTTPLifConf":    {"location_if"},
	"ngxHTTPLmtConf":    {"limit_except"},
	"ngxAnyConf": {
		"main", "events", "mail", "mail_server", "stream", "stream_server",
		"stream_upstream", "http", "server", "location", "upstream", "server_if",
		"location_if", "limit_except",
	},
}

var counts = map[string][]int{
	"ngxConfNoArgs": {0}, "ngxConfTake1": {1}, "ngxConfTake2": {2}, "ngxConfTake3": {3}, "ngxConfTake4": {4},
	"ngxConfTake5": {5}, "ngxConfTake6": {6}, "ngxConfTake7": {7}, "ngxConfTake12": {1, 2}, "ngxConfTake13": {1, 3},
	"ngxConfTake23": {2, 3}, "ngxConfTake34": {3, 4}, "ngxConfTake123": {1, 2, 3}, "ngxConfTake1234": {1, 2, 3, 4},
}

type form struct {
	Contexts []string `json:"ctx"`
	Args     []int    `json:"args,omitempty"`
	Min      int      `json:"min,omitempty"`
	More     bool     `json:"more,omitempty"`
	Flag     bool     `json:"flag,omitempty"`
	Block    bool     `json:"block,omitempty"`
}

type table struct {
	Source     string            `json:"source"`
	Directives map[string][]form `json:"directives"`
}

var (
	nameRe = regexp.MustCompile(`^\s*"([^"]+)": \{$`)
	maskRe = regexp.MustCompile(`^\s*(ngx[A-Za-z0-9 |]+),$`)
)

func parse(mask string) (form, error) {
	var f form
	for part := range strings.SplitSeq(mask, "|") {
		part = strings.TrimSpace(part)
		switch {
		case contexts[part] != nil:
			f.Contexts = append(f.Contexts, contexts[part]...)
		case counts[part] != nil:
			f.Args = append(f.Args, counts[part]...)
		case part == "ngxConfBlock":
			f.Block = true
		case part == "ngxConfFlag":
			f.Flag = true
		case part == "ngxConfAny":
			f.More = true
		case part == "ngxConf1More":
			f.More, f.Min = true, 1
		case part == "ngxConf2More":
			f.More, f.Min = true, 2
		case part == "ngxDirectConf", part == "ngxConfExpr":
		default:
			return f, fmt.Errorf("unknown mask %q", part)
		}
	}
	if f.Flag || f.More {
		f.Args = nil
	}
	return f, nil
}

func run(genPath, source, out string) error {
	in, err := os.Open(genPath)
	if err != nil {
		return err
	}
	defer in.Close()
	t := table{Source: source, Directives: map[string][]form{}}
	name := ""
	sc := bufio.NewScanner(in)
	for sc.Scan() {
		if m := nameRe.FindStringSubmatch(sc.Text()); m != nil {
			name = m[1]
			continue
		}
		if m := maskRe.FindStringSubmatch(sc.Text()); m != nil && name != "" {
			f, err := parse(m[1])
			if err != nil {
				return fmt.Errorf("%s: %w", name, err)
			}
			t.Directives[name] = append(t.Directives[name], f)
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	if len(t.Directives) < 100 {
		return fmt.Errorf("only %d directives parsed", len(t.Directives))
	}
	data, err := json.MarshalIndent(t, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(out, append(data, '\n'), 0o644)
}

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: directives <generated.go> <source> <out.json>")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2], os.Args[3]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
