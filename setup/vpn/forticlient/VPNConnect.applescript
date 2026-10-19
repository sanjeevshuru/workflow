-- VPN Connect: clicks FortiClient's SAML Login / Disconnect for the `vpn` command, so nobody has to.
--
-- macOS only lets an app drive another app's window when the user has allowed it under
-- Privacy & Security -> Accessibility. Two ways to run this script (setup/vpn/vpn picks one):
--   1. As ~/Applications/VPN Connect.app (setup/vpn/install-applet.sh): only that app needs the
--      permission. Protocol, since an applet gets no arguments:
--        ~/Library/Caches/vpn-connect/request   one word: connect | disconnect | status | dump | check
--        ~/Library/Caches/vpn-connect/result    first line: ok: … | error: …, then details
--   2. Directly: osascript VPNConnect.applescript <word>. The result goes to stdout, and the app
--      that started osascript (Terminal, VS Code, …) needs the permission.
-- Either way it only ever touches the FortiClient process and only accepts the five words above.
-- Adapted with ideas from a teammate's fortiauto script (refuse ambiguous clicks).

property connectLabels : {"SAML Login", "Connect"}
property disconnectLabels : {"Disconnect"}
property navLabels : {"Remote Access"}

on run argv
	set direct to false
	set req to ""
	try
		if (count of argv) > 0 then
			set direct to true
			set req to item 1 of argv
		end if
	end try
	set stateDir to (POSIX path of (path to home folder)) & "Library/Caches/vpn-connect/"
	if not direct then
		do shell script "mkdir -p " & quoted form of stateDir
		try
			set req to do shell script "f=" & quoted form of (stateDir & "request") & "; cat \"$f\" 2>/dev/null; rm -f \"$f\""
		end try
	end if
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
		if n is -1719 or n is -25211 or n is -1743 or msg contains "assistive access" or msg contains "not allowed to send" then
			if direct then
				set who to "the app running this command (Terminal, VS Code, …)"
			else
				set who to "'VPN Connect'"
			end if
			set res to "error: not allowed (" & n & "): allow " & who & " in System Settings > Privacy & Security > Accessibility (and Automation > System Events)"
		else
			set res to "error: " & n & " " & msg
		end if
	end try
	if direct then return res
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
					if (count of windows) > 0 then
						-- FortiClient's tree goes stale in the background (it kept showing "VPN Connected"
						-- 36 s after a disconnect). Turning Electron's accessibility off and on rebuilds it.
						try
							set value of attribute "AXManualAccessibility" to false
							delay 0.3
						end try
						try
							set value of attribute "AXManualAccessibility" to true
						end try
						delay 1
						return window 1
					end if
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

-- Every element under w, walked level by level. `entire contents` doesn't descend into Electron's
-- AXWebArea (it returns nothing for FortiClient 7.4), so the tree is walked by hand.
on allElements(w)
	return my collect(w, 0, {})
end allElements

on collect(e, depth, acc)
	if depth > 20 then return acc
	set kids to {}
	tell application "System Events"
		try
			set kids to UI elements of e
		end try
	end tell
	repeat with k in kids
		set end of acc to (contents of k)
		set acc to my collect(contents of k, depth + 1, acc)
	end repeat
	return acc
end collect

-- Every element of the given role whose label equals the label.
on allByLabel(w, wantedRole, wanted)
	set found to {}
	repeat with e in my allElements(w)
		if my roleOf(e) is wantedRole then
			set l to my labelOf(e)
			if l is wanted or l starts with (wanted & " |") then set end of found to (contents of e)
		end if
	end repeat
	return found
end allByLabel

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
	-- Never guess: refuse when the chosen label matches more than one button.
	set same to my allByLabel(w, "AXButton", l)
	if (count of same) > 1 then error "found " & (count of same) & " '" & l & "' buttons; refusing an ambiguous click (run: vpn dump)" number 1003
	my press(b)
	return "ok: clicked " & l
end doConnect

on doDisconnect()
	set w to my fortiWindow()
	set b to my findByLabel(w, "AXButton", disconnectLabels)
	if b is missing value then return "ok: already disconnected"
	set l to my labelOf(b)
	my press(b)
	return "ok: clicked " & l
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
