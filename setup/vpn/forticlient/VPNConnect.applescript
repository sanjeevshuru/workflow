-- VPN Connect: clicks FortiClient's SAML Login / Disconnect for the `vpn` command, so nobody has to.
--
-- macOS only lets an app drive another app's window when the user has allowed it under
-- Privacy & Security -> Accessibility. This applet is that app: it gets the permission, not the
-- editor or terminal. It only ever touches the FortiClient process.
--
-- Protocol (setup/vpn/vpn writes and reads these; nothing else is accepted):
--   ~/Library/Caches/vpn-connect/request   one word: connect | disconnect | status | dump | check
--   ~/Library/Caches/vpn-connect/result    first line: ok: … | error: …, then details
--
-- Built by setup/vpn/install-applet.sh into ~/Applications/VPN Connect.app.

property connectLabels : {"SAML Login", "Connect"}
property disconnectLabels : {"Disconnect"}
property connectedTexts : {"VPN Connected", "Connected"}
property navLabels : {"Remote Access"}

on run
	set stateDir to (POSIX path of (path to home folder)) & "Library/Caches/vpn-connect/"
	do shell script "mkdir -p " & quoted form of stateDir
	set req to ""
	try
		set req to do shell script "f=" & quoted form of (stateDir & "request") & "; cat \"$f\" 2>/dev/null; rm -f \"$f\""
	end try
	set res to "error: no request"
	try
		if req is "connect" then
			set res to doConnect()
		else if req is "disconnect" then
			set res to doDisconnect()
		else if req is "status" then
			set res to doStatus()
		else if req is "dump" then
			set res to doDump()
		else if req is "check" then
			set res to doCheck()
		else if req is not "" then
			set res to "error: unknown request " & req
		end if
	on error msg number n
		if n is -1719 or n is -25211 or n is -1743 then
			set res to "error: not allowed (" & n & "): allow 'VPN Connect' in System Settings > Privacy & Security > Accessibility (and Automation > System Events)"
		else
			set res to "error: " & n & " " & msg
		end if
	end try
	set tmp to stateDir & "result.tmp"
	do shell script "printf '%s\\n' " & quoted form of res & " > " & quoted form of tmp & " && mv " & quoted form of tmp & " " & quoted form of (stateDir & "result")
end run

-- Makes sure FortiClient runs with a window, without bringing it to the front, and exposes its
-- Electron accessibility tree. Returns the window.
on fortiWindow()
	do shell script "open -g -a FortiClient"
	tell application "System Events"
		repeat 40 times
			if exists process "FortiClient" then
				tell process "FortiClient"
					try
						set value of attribute "AXManualAccessibility" to true
					end try
					if (count of windows) > 0 then return window 1
				end tell
			end if
			delay 0.25
		end repeat
	end tell
	error "FortiClient has no window" number 1001
end fortiWindow

on labelOf(e)
	set parts to {}
	tell application "System Events"
		repeat with getter in {"AXTitle", "AXDescription", "AXValue"}
			try
				set v to value of attribute (contents of getter) of e
				if v is not missing value and (class of v is text) and v is not "" then set end of parts to v
			end try
		end repeat
		try
			set v to name of e
			if v is not missing value and v is not "" and parts does not contain v then set end of parts to v
		end try
	end tell
	set AppleScript's text item delimiters to " | "
	set s to parts as text
	set AppleScript's text item delimiters to ""
	return s
end labelOf

on roleOf(e)
	tell application "System Events"
		try
			return role of e
		on error
			return "?"
		end try
	end tell
end roleOf

on allElements(w)
	tell application "System Events" to return entire contents of w
end allElements

-- First element of the given role whose label equals one of the labels (in the order given).
on findByLabel(w, wantedRole, labels)
	set els to my allElements(w)
	repeat with wanted in labels
		repeat with e in els
			if my roleOf(e) is wantedRole then
				set l to my labelOf(e)
				if l is (contents of wanted) or l starts with ((contents of wanted) & " |") then return e
			end if
		end repeat
	end repeat
	return missing value
end findByLabel

on hasText(w, texts)
	set els to my allElements(w)
	repeat with e in els
		set l to my labelOf(e)
		repeat with t in texts
			if l is (contents of t) or l starts with ((contents of t) & " |") then return true
		end repeat
	end repeat
	return false
end hasText

on press(e)
	tell application "System Events"
		try
			perform action "AXPress" of e
		on error
			click e
		end try
	end tell
end press

on currentState(w)
	if my findByLabel(w, "AXButton", disconnectLabels) is not missing value then return "connected"
	if my findByLabel(w, "AXButton", connectLabels) is not missing value then return "disconnected"
	return "unknown"
end currentState

on doCheck()
	set w to my fortiWindow()
	return "ok: allowed; window '" & my labelOf(w) & "'"
end doCheck

on doStatus()
	set w to my fortiWindow()
	return "ok: " & my currentState(w)
end doStatus

on doConnect()
	set w to my fortiWindow()
	set b to my findByLabel(w, "AXButton", connectLabels)
	if b is missing value then
		if my findByLabel(w, "AXButton", disconnectLabels) is not missing value then return "ok: already connected"
		-- Maybe another page is showing: open Remote Access and look again.
		repeat with nav in navLabels
			set n to my findByLabel(w, "AXButton", {contents of nav})
			if n is missing value then set n to my findByLabel(w, "AXLink", {contents of nav})
			if n is missing value then set n to my findByLabel(w, "AXStaticText", {contents of nav})
			if n is not missing value then
				my press(n)
				delay 1
				set b to my findByLabel(w, "AXButton", connectLabels)
				exit repeat
			end if
		end repeat
	end if
	if b is missing value then error "no SAML Login / Connect button found (run: vpn dump)" number 1002
	set l to my labelOf(b)
	my press(b)
	return "ok: clicked " & l
end doConnect

on doDisconnect()
	set w to my fortiWindow()
	set b to my findByLabel(w, "AXButton", disconnectLabels)
	if b is missing value then return "ok: already disconnected"
	my press(b)
	return "ok: clicked " & my labelOf(b)
end doDisconnect

-- Every element with a label: role, then label. Used to adapt the labels above to a FortiClient version.
on doDump()
	set w to my fortiWindow()
	set out to {"ok: dump of '" & my labelOf(w) & "'"}
	repeat with e in my allElements(w)
		set l to my labelOf(e)
		if l is not "" then set end of out to my roleOf(e) & "  " & l
	end repeat
	set AppleScript's text item delimiters to linefeed
	set s to out as text
	set AppleScript's text item delimiters to ""
	return s
end doDump
