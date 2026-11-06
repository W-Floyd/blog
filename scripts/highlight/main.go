// Renders a file to the same HTML Hugo's highlighter emits, using a newer
// chroma than Hugo ships (for lexers such as jq that Hugo doesn't have yet).
package main

import (
	"fmt"
	"os"

	"github.com/alecthomas/chroma/v3/formatters/html"
	"github.com/alecthomas/chroma/v3/lexers"
	"github.com/alecthomas/chroma/v3/styles"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: highlight <lang> <file>")
		os.Exit(2)
	}
	lang, path := os.Args[1], os.Args[2]
	src, err := os.ReadFile(path)
	check(err)
	lexer := lexers.Get(lang)
	if lexer == nil {
		check(fmt.Errorf("no lexer for %q", lang))
	}
	it, err := lexer.Tokenise(nil, string(src))
	check(err)
	// Matches Hugo's defaults: monokai, inline styles, tab width 4.
	f := html.New(html.TabWidth(4), html.WithPreWrapper(hugoWrapper(lang)))
	check(f.Format(os.Stdout, styles.Get("monokai"), it))
	fmt.Println()
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// hugoWrapper reproduces the markup around Hugo's highlighted code blocks.
type hugoWrapper string

func (l hugoWrapper) Start(code bool, styleAttr string) string {
	return fmt.Sprintf(`<div class="highlight"><pre tabindex="0"%s><code class="language-%s" data-lang="%s">`, styleAttr, l, l)
}

func (hugoWrapper) End(code bool) string { return "</code></pre></div>" }
