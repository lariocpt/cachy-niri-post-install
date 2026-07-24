# Yazi wrapper to sync cwd and act as a picker to "drop into the action"
function yazi-sync() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	local choose="$(mktemp -t "yazi-choose.XXXXXX")"
	
	# Run yazi with chooser-file so pressing Enter selects a file and quits Yazi
	yazi "$@" --cwd-file="$tmp" --chooser-file="$choose"
	
	# Sync directory if changed
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
	
	# If a file was selected, Yazi has closed; now drop into the action (opn)
	if [ -s "$choose" ]; then
		local file="$(cat -- "$choose")"
		rm -f -- "$choose"
		# Execute opn on the selected file in the same terminal
		opn "$file"
	else
		rm -f -- "$choose"
	fi
}
alias y=yazi-sync
alias yz=yazi-sync

# Broot simply launches in the current shell, but yazi-opener-config generates
# openers.hjson such that selecting a file in broot spawns a NEW ghostty terminal
alias br="broot"
alias broot="broot"
