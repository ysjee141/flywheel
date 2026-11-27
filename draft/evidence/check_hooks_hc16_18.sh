P="Run exactly this bash command once, then stop: touch MARK"
DENY='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo no >&2; exit 2"}]}]}}'
tst(){ id=$1; src=$2; set_=$3; prompt=$4; shift 4; rm -rf $id; mkdir -p $id/.claude; cd $id; git init -q .; [ -n "$PROJ" ] && echo "$PROJ" > .claude/settings.json; echo "$set_" > ../$id.json
 timeout 120 claude -p "$prompt" --model haiku --setting-sources "$src" --settings ../$id.json --strict-mcp-config --tools Bash "$@" --max-budget-usd 0.2 --output-format json > ../$id.out 2>../$id.err </dev/null
 echo "$id rc=$? MARK=$([ -e MARK ] && echo yes || echo no) $(jq -r .result ../$id.out|head -c 140|tr '\n' ' ') $(head -c 150 ../$id.err)"; }
(PROJ='{"disableAllHooks":true}'; tst HC16a project "$DENY" "$P" --allowedTools "Bash(touch:*)") &
(PROJ='{"disableAllHooks":true}'; tst HC16b "" "$DENY" "$P" --allowedTools "Bash(touch:*)") &
(PROJ=; tst HC17a "" '{"permissions":{"allow":["Bash"],"deny":["Bash(touch:*)"]}}' "$P") &
(PROJ=; tst HC17b "" '{"permissions":{"allow":["Bash"],"deny":["Bash(touch:*)"]}}' "Run exactly this bash command once, then stop: python3 -c \"open('MARK','w')\"") &
(PROJ=; tst HC18 "" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"jq -e \".tool_input.command|test(\\\"^touch\\\")|not\" >/dev/null || exit 2"}]}]}}' "Run exactly this bash command once, then stop: bash -c 'touch MARK'" --allowedTools "Bash") &
wait
