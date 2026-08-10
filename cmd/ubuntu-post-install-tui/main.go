package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type screen uint8

const (
	selectScreen screen = iota
	reviewScreen
	runScreen
	summaryScreen
)

type itemStatus uint8

const (
	available itemStatus = iota
	alreadyCompleted
	queued
	running
	succeeded
	failed
	skipped
	cancelled
)

type item struct {
	categoryID string
	label      string
	script     string
	selected   bool
	status     itemStatus
	duration   time.Duration
}

type category struct {
	id      string
	label   string
	indices []int
}

type options struct {
	root      string
	catalog   string
	markerDir string
	logFile   string
	version   string
}

type scriptFinishedMsg struct {
	index    int
	err      error
	duration time.Duration
}

type model struct {
	opts          options
	categories    []category
	items         []item
	screen        screen
	category      int
	cursor        int
	width         int
	height        int
	queue         []int
	queuePosition int
	notice        string
}

var (
	accentColor   = lipgloss.Color("#7D56F4")
	cyanColor     = lipgloss.Color("#5FD7FF")
	greenColor    = lipgloss.Color("#5FD787")
	yellowColor   = lipgloss.Color("#FFD75F")
	redColor      = lipgloss.Color("#FF5F6D")
	mutedColor    = lipgloss.Color("#7C8191")
	headerStyle   = lipgloss.NewStyle().Bold(true).Foreground(accentColor)
	sectionStyle  = lipgloss.NewStyle().Bold(true).Foreground(cyanColor)
	mutedStyle    = lipgloss.NewStyle().Foreground(mutedColor)
	selectedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF")).
			Background(accentColor).
			Bold(true)
	panelStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accentColor).
			Padding(1, 2)
)

func main() {
	opts, checkOnly, err := parseOptions(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	categories, items, err := loadCatalog(opts.root, opts.catalog, opts.markerDir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "catalog:", err)
		os.Exit(1)
	}
	if checkOnly {
		fmt.Printf("catalog OK: %d items in %d categories\n", len(items), len(categories))
		return
	}

	m := model{
		opts:       opts,
		categories: categories,
		items:      items,
		screen:     selectScreen,
		width:      80,
		height:     24,
	}
	if _, err := tea.NewProgram(m).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "terminal UI:", err)
		os.Exit(1)
	}
}

func parseOptions(args []string) (options, bool, error) {
	executable, err := os.Executable()
	if err != nil {
		return options{}, false, fmt.Errorf("resolve executable: %w", err)
	}
	defaultRoot := filepath.Dir(filepath.Dir(executable))
	defaultHome, err := os.UserHomeDir()
	if err != nil {
		return options{}, false, fmt.Errorf("resolve home directory: %w", err)
	}

	flags := flag.NewFlagSet("ubuntu-post-install-tui", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	root := flags.String("root", defaultRoot, "installer repository root")
	catalogPath := flags.String("catalog", "", "installer catalog")
	markerDir := flags.String("marker-dir", filepath.Join(defaultHome, ".cache", "ubuntu-setup"), "completion marker directory")
	logFile := flags.String("log-file", filepath.Join(defaultHome, "ubuntu-setup.log"), "installer log")
	version := flags.String("version", "dev", "installer version")
	checkOnly := flags.Bool("check", false, "validate the catalog and exit")
	if err := flags.Parse(args); err != nil {
		return options{}, false, err
	}
	if flags.NArg() != 0 {
		return options{}, false, fmt.Errorf("unexpected arguments: %s", strings.Join(flags.Args(), " "))
	}

	cleanRoot, err := filepath.Abs(*root)
	if err != nil {
		return options{}, false, fmt.Errorf("resolve root: %w", err)
	}
	cleanCatalog := *catalogPath
	if cleanCatalog == "" {
		cleanCatalog = filepath.Join(cleanRoot, "config", "catalog.txt")
	}
	cleanCatalog, err = filepath.Abs(cleanCatalog)
	if err != nil {
		return options{}, false, fmt.Errorf("resolve catalog: %w", err)
	}
	cleanMarkerDir, err := filepath.Abs(*markerDir)
	if err != nil {
		return options{}, false, fmt.Errorf("resolve marker directory: %w", err)
	}
	cleanLogFile, err := filepath.Abs(*logFile)
	if err != nil {
		return options{}, false, fmt.Errorf("resolve log file: %w", err)
	}

	return options{
		root:      cleanRoot,
		catalog:   cleanCatalog,
		markerDir: cleanMarkerDir,
		logFile:   cleanLogFile,
		version:   *version,
	}, *checkOnly, nil
}

func loadCatalog(root, catalogPath, markerDir string) ([]category, []item, error) {
	file, err := os.Open(catalogPath)
	if err != nil {
		return nil, nil, err
	}
	defer file.Close()

	var categories []category
	var items []item
	categoryIndex := make(map[string]int)
	seenScripts := make(map[string]struct{})
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.SplitN(line, "|", 4)
		if len(fields) != 4 {
			return nil, nil, fmt.Errorf("line %d: expected four pipe-delimited fields", lineNumber)
		}
		for index := range fields {
			fields[index] = strings.TrimSpace(fields[index])
		}
		categoryID, categoryLabel, label, script := fields[0], fields[1], fields[2], fields[3]
		if !validCategoryID(categoryID) || categoryLabel == "" || label == "" {
			return nil, nil, fmt.Errorf("line %d: invalid category or label", lineNumber)
		}
		cleanScript := filepath.ToSlash(filepath.Clean(script))
		if filepath.IsAbs(script) || cleanScript == "." || cleanScript == ".." || strings.HasPrefix(cleanScript, "../") {
			return nil, nil, fmt.Errorf("line %d: unsafe script path %q", lineNumber, script)
		}
		if _, duplicate := seenScripts[cleanScript]; duplicate {
			return nil, nil, fmt.Errorf("line %d: duplicate script %q", lineNumber, cleanScript)
		}
		info, err := os.Stat(filepath.Join(root, filepath.FromSlash(cleanScript)))
		if err != nil || info.IsDir() {
			return nil, nil, fmt.Errorf("line %d: missing script %q", lineNumber, cleanScript)
		}
		seenScripts[cleanScript] = struct{}{}

		index, exists := categoryIndex[categoryID]
		if !exists {
			index = len(categories)
			categoryIndex[categoryID] = index
			categories = append(categories, category{id: categoryID, label: categoryLabel})
		} else if categories[index].label != categoryLabel {
			return nil, nil, fmt.Errorf("line %d: conflicting label for category %q", lineNumber, categoryID)
		}

		status := available
		if fileExists(markerPath(markerDir, cleanScript)) {
			status = alreadyCompleted
		}
		itemIndex := len(items)
		items = append(items, item{
			categoryID: categoryID,
			label:      label,
			script:     cleanScript,
			status:     status,
		})
		categories[index].indices = append(categories[index].indices, itemIndex)
	}
	if err := scanner.Err(); err != nil {
		return nil, nil, err
	}
	if len(items) == 0 {
		return nil, nil, errors.New("catalog is empty")
	}
	return categories, items, nil
}

func validCategoryID(value string) bool {
	if value == "" || value[0] < 'a' || value[0] > 'z' {
		return false
	}
	for _, char := range value[1:] {
		if (char < 'a' || char > 'z') && (char < '0' || char > '9') && char != '-' {
			return false
		}
	}
	return true
}

func markerPath(markerDir, script string) string {
	name := strings.NewReplacer("/", "_", "\\", "_").Replace(script) + ".done"
	return filepath.Join(markerDir, name)
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := message.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil
	case scriptFinishedMsg:
		return m.finishScript(msg)
	case tea.KeyPressMsg:
		return m.handleKey(msg.String())
	default:
		return m, nil
	}
}

func (m model) handleKey(key string) (tea.Model, tea.Cmd) {
	switch m.screen {
	case selectScreen:
		return m.handleSelectionKey(key)
	case reviewScreen:
		return m.handleReviewKey(key)
	case runScreen:
		return m, nil
	case summaryScreen:
		return m.handleSummaryKey(key)
	default:
		return m, nil
	}
}

func (m model) handleSelectionKey(key string) (tea.Model, tea.Cmd) {
	indices := m.categories[m.category].indices
	switch key {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "left", "h":
		if m.category > 0 {
			m.category--
			m.cursor = 0
		}
	case "right", "l":
		if m.category < len(m.categories)-1 {
			m.category++
			m.cursor = 0
		}
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < len(indices)-1 {
			m.cursor++
		}
	case "pgup":
		m.cursor -= 8
		if m.cursor < 0 {
			m.cursor = 0
		}
	case "pgdown":
		m.cursor += 8
		if m.cursor >= len(indices) {
			m.cursor = len(indices) - 1
		}
	case "space":
		index := indices[m.cursor]
		m.items[index].selected = !m.items[index].selected
		m.notice = ""
	case "a":
		selectItems := false
		for _, index := range indices {
			if !m.items[index].selected {
				selectItems = true
				break
			}
		}
		for _, index := range indices {
			m.items[index].selected = selectItems
		}
		m.notice = ""
	case "ctrl+a":
		for index := range m.items {
			m.items[index].selected = true
		}
		m.notice = ""
	case "x":
		for index := range m.items {
			m.items[index].selected = false
		}
		m.notice = "Selection cleared"
	case "enter":
		if m.selectedCount() == 0 {
			m.notice = "Select at least one item before continuing"
			return m, nil
		}
		m.screen = reviewScreen
		m.notice = ""
	}
	return m, nil
}

func (m model) handleReviewKey(key string) (tea.Model, tea.Cmd) {
	switch key {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "backspace":
		m.screen = selectScreen
		return m, nil
	case "enter":
		m.queue = m.selectedIndices()
		m.queuePosition = 0
		for _, index := range m.queue {
			m.items[index].status = queued
		}
		m.screen = runScreen
		return m.startNextScript()
	default:
		return m, nil
	}
}

func (m model) handleSummaryKey(key string) (tea.Model, tea.Cmd) {
	switch key {
	case "q", "ctrl+c", "enter":
		return m, tea.Quit
	case "l":
		if _, err := exec.LookPath("less"); err != nil {
			m.notice = "Install 'less' to open the log pager"
			return m, nil
		}
		command := exec.Command("less", "-R", m.opts.logFile)
		return m, tea.ExecProcess(command, func(err error) tea.Msg {
			return scriptFinishedMsg{index: -1, err: err}
		})
	case "r":
		m.queue = m.failedIndices()
		if len(m.queue) == 0 {
			m.notice = "There are no failed items to retry"
			return m, nil
		}
		m.queuePosition = 0
		for _, index := range m.queue {
			m.items[index].status = queued
		}
		m.screen = runScreen
		m.notice = ""
		return m.startNextScript()
	default:
		return m, nil
	}
}

func (m model) startNextScript() (tea.Model, tea.Cmd) {
	for m.queuePosition < len(m.queue) {
		index := m.queue[m.queuePosition]
		if fileExists(markerPath(m.opts.markerDir, m.items[index].script)) {
			m.items[index].status = skipped
			m.queuePosition++
			continue
		}

		m.items[index].status = running
		started := time.Now()
		command := exec.Command("/bin/bash", filepath.Join(m.opts.root, "setup.sh"), "--run-item", m.items[index].script)
		command.Dir = m.opts.root
		command.Env = append(os.Environ(), "UPI_PROGRESS="+strconv.Itoa(m.queuePosition+1)+"/"+strconv.Itoa(len(m.queue)))
		return m, tea.ExecProcess(command, func(err error) tea.Msg {
			return scriptFinishedMsg{index: index, err: err, duration: time.Since(started)}
		})
	}
	m.screen = summaryScreen
	return m, nil
}

func (m model) finishScript(msg scriptFinishedMsg) (tea.Model, tea.Cmd) {
	if msg.index < 0 {
		if msg.err != nil {
			m.notice = "Could not open the log: " + msg.err.Error()
		}
		return m, nil
	}
	m.items[msg.index].duration = msg.duration
	if msg.err == nil {
		m.items[msg.index].status = succeeded
	} else if interrupted(msg.err) {
		m.items[msg.index].status = cancelled
		for position := m.queuePosition + 1; position < len(m.queue); position++ {
			m.items[m.queue[position]].status = cancelled
		}
		m.screen = summaryScreen
		m.notice = "Installation stopped during " + m.items[msg.index].label
		return m, nil
	} else {
		m.items[msg.index].status = failed
	}
	m.queuePosition++
	return m.startNextScript()
}

func interrupted(err error) bool {
	var exitError *exec.ExitError
	if errors.As(err, &exitError) && exitError.ExitCode() == 130 {
		return true
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "interrupt") || strings.Contains(message, "signal: killed")
}

func (m model) selectedCount() int {
	count := 0
	for _, current := range m.items {
		if current.selected {
			count++
		}
	}
	return count
}

func (m model) selectedIndices() []int {
	indices := make([]int, 0, m.selectedCount())
	for index, current := range m.items {
		if current.selected {
			indices = append(indices, index)
		}
	}
	return indices
}

func (m model) failedIndices() []int {
	var indices []int
	for index, current := range m.items {
		if current.status == failed || current.status == cancelled {
			indices = append(indices, index)
		}
	}
	return indices
}

func (m model) View() tea.View {
	var content string
	if m.width < 52 || m.height < 16 {
		content = place(
			headerStyle.Render("Terminal too small")+"\n\n"+
				fmt.Sprintf("Resize to at least 52×16. Current size: %d×%d\n\n", m.width, m.height)+
				mutedStyle.Render("q quit"),
			m.width,
			m.height,
		)
	} else {
		switch m.screen {
		case selectScreen:
			content = m.selectionView()
		case reviewScreen:
			content = m.reviewView()
		case runScreen:
			content = m.runView()
		case summaryScreen:
			content = m.summaryView()
		}
	}
	view := tea.NewView(content)
	view.AltScreen = true
	view.WindowTitle = "Ubuntu Post Install"
	return view
}

func (m model) selectionView() string {
	currentCategory := m.categories[m.category]
	selected := m.selectedCount()
	panelWidth := clamp(m.width-6, 54, 104)
	innerWidth := panelWidth - 6
	visibleRows := clamp(m.height-13, 5, len(currentCategory.indices))
	start := 0
	if m.cursor >= visibleRows {
		start = m.cursor - visibleRows + 1
	}
	end := start + visibleRows
	if end > len(currentCategory.indices) {
		end = len(currentCategory.indices)
	}

	var body strings.Builder
	body.WriteString(headerStyle.Render("UBUNTU POST INSTALL"))
	body.WriteString("  ")
	body.WriteString(mutedStyle.Render("v" + m.opts.version))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render("Build your development environment, one deliberate choice at a time."))
	body.WriteString("\n\n")
	body.WriteString(sectionStyle.Render(fmt.Sprintf("‹  %d/%d  %s  ›", m.category+1, len(m.categories), currentCategory.label)))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render(fmt.Sprintf("%d selected overall · %d items in this category", selected, len(currentCategory.indices))))
	body.WriteString("\n\n")

	for row := start; row < end; row++ {
		index := currentCategory.indices[row]
		current := m.items[index]
		checkbox := "[ ]"
		if current.selected {
			checkbox = "[✓]"
		} else if current.status == alreadyCompleted {
			checkbox = "[•]"
		}
		line := fmt.Sprintf("  %s  %s", checkbox, truncate(current.label, innerWidth-8))
		if row == m.cursor {
			line = selectedStyle.Width(innerWidth).Render("  " + checkbox + "  " + truncate(current.label, innerWidth-8))
		} else if current.status == alreadyCompleted {
			line = lipgloss.NewStyle().Foreground(greenColor).Render(line) + mutedStyle.Render("  completed")
		}
		body.WriteString(line)
		body.WriteString("\n")
	}

	body.WriteString("\n")
	if m.notice != "" {
		body.WriteString(lipgloss.NewStyle().Foreground(yellowColor).Render("! " + m.notice))
		body.WriteString("\n")
	}
	body.WriteString(mutedStyle.Render("←/→ category  ↑/↓ navigate  space select  a category  ctrl+a all  enter review  q quit"))
	return place(panelStyle.Width(panelWidth).Render(body.String()), m.width, m.height)
}

func (m model) reviewView() string {
	panelWidth := clamp(m.width-6, 54, 104)
	innerWidth := panelWidth - 6
	selected := m.selectedIndices()
	visibleRows := clamp(m.height-14, 4, len(selected))

	var body strings.Builder
	body.WriteString(headerStyle.Render("REVIEW INSTALLATION"))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render(fmt.Sprintf("%d item(s) will run in the recommended catalog order.", len(selected))))
	body.WriteString("\n\n")
	for position, index := range selected {
		if position >= visibleRows {
			body.WriteString(mutedStyle.Render(fmt.Sprintf("  … and %d more", len(selected)-position)))
			body.WriteString("\n")
			break
		}
		current := m.items[index]
		status := ""
		if current.status == alreadyCompleted {
			status = " " + lipgloss.NewStyle().Foreground(greenColor).Render("(will skip)")
		}
		body.WriteString(fmt.Sprintf("  %2d. %s%s\n", position+1, truncate(current.label, innerWidth-10), status))
	}
	body.WriteString("\n")
	body.WriteString(lipgloss.NewStyle().Foreground(yellowColor).Render("Administrative or passphrase prompts will temporarily take over this terminal."))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render("enter install  esc edit selection  q quit"))
	return place(panelStyle.Width(panelWidth).Render(body.String()), m.width, m.height)
}

func (m model) runView() string {
	panelWidth := clamp(m.width-6, 54, 104)
	total := len(m.queue)
	completed := m.queuePosition
	currentLabel := "Preparing next item…"
	if m.queuePosition < total {
		currentLabel = m.items[m.queue[m.queuePosition]].label
	}
	barWidth := clamp(panelWidth-14, 20, 70)

	var body strings.Builder
	body.WriteString(headerStyle.Render("INSTALLING"))
	body.WriteString("\n\n")
	body.WriteString(progressBar(completed, total, barWidth))
	body.WriteString(fmt.Sprintf("  %d/%d\n\n", completed, total))
	body.WriteString(sectionStyle.Render("● " + currentLabel))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render("The live installer now owns the terminal. This screen returns when it exits."))
	return place(panelStyle.Width(panelWidth).Render(body.String()), m.width, m.height)
}

func (m model) summaryView() string {
	panelWidth := clamp(m.width-6, 54, 104)
	innerWidth := panelWidth - 6
	selected := m.selectedIndices()
	visibleRows := clamp(m.height-15, 4, len(selected))
	counts := make(map[itemStatus]int)
	for _, index := range selected {
		counts[m.items[index].status]++
	}

	var body strings.Builder
	body.WriteString(headerStyle.Render("INSTALLATION SUMMARY"))
	body.WriteString("\n")
	body.WriteString(
		lipgloss.NewStyle().Foreground(greenColor).Render(fmt.Sprintf("✓ %d succeeded", counts[succeeded])) + "   " +
			lipgloss.NewStyle().Foreground(redColor).Render(fmt.Sprintf("✗ %d failed", counts[failed])) + "   " +
			lipgloss.NewStyle().Foreground(yellowColor).Render(fmt.Sprintf("↷ %d skipped", counts[skipped])) + "   " +
			mutedStyle.Render(fmt.Sprintf("%d cancelled", counts[cancelled])),
	)
	body.WriteString("\n\n")
	for position, index := range selected {
		if position >= visibleRows {
			body.WriteString(mutedStyle.Render(fmt.Sprintf("  … and %d more", len(selected)-position)))
			body.WriteString("\n")
			break
		}
		current := m.items[index]
		icon, style := statusPresentation(current.status)
		duration := ""
		if current.duration > 0 {
			duration = mutedStyle.Render("  " + current.duration.Round(time.Second).String())
		}
		body.WriteString(style.Render(fmt.Sprintf("  %s %s", icon, truncate(current.label, innerWidth-14))))
		body.WriteString(duration)
		body.WriteString("\n")
	}
	body.WriteString("\n")
	if m.notice != "" {
		body.WriteString(lipgloss.NewStyle().Foreground(yellowColor).Render("! " + m.notice))
		body.WriteString("\n")
	}
	body.WriteString(mutedStyle.Render("r retry failed  l open full log  enter/q exit"))
	body.WriteString("\n")
	body.WriteString(mutedStyle.Render("Log: " + m.opts.logFile))
	return place(panelStyle.Width(panelWidth).Render(body.String()), m.width, m.height)
}

func statusPresentation(status itemStatus) (string, lipgloss.Style) {
	switch status {
	case succeeded:
		return "✓", lipgloss.NewStyle().Foreground(greenColor)
	case failed:
		return "✗", lipgloss.NewStyle().Foreground(redColor)
	case skipped, alreadyCompleted:
		return "↷", lipgloss.NewStyle().Foreground(yellowColor)
	case cancelled:
		return "■", mutedStyle
	case running:
		return "●", lipgloss.NewStyle().Foreground(cyanColor)
	default:
		return "○", mutedStyle
	}
}

func progressBar(completed, total, width int) string {
	if total <= 0 {
		return strings.Repeat("─", width)
	}
	filled := completed * width / total
	return lipgloss.NewStyle().Foreground(accentColor).Render(strings.Repeat("━", filled)) +
		mutedStyle.Render(strings.Repeat("─", width-filled))
}

func place(content string, width, height int) string {
	if width <= 0 || height <= 0 {
		return content
	}
	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, content)
}

func clamp(value, minimum, maximum int) int {
	if maximum < minimum {
		return maximum
	}
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func truncate(value string, width int) string {
	if width <= 0 {
		return ""
	}
	if utf8.RuneCountInString(value) <= width {
		return value
	}
	if width == 1 {
		return "…"
	}
	runes := []rune(value)
	return string(runes[:width-1]) + "…"
}
