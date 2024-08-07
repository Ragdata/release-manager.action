#!/bin/bash
# vim: set foldlevel=0 foldmethod=marker:
# shellcheck disable=SC2317

# Import once
[[ -z $__BPT_VERSION ]] || return
readonly __BPT_VERSION="v0.3"

# The shift-reduce LR(1) parser.
# $1: Parse table name.
#   The parse table should be an associative array where the key is
#   <state>,<token> and the value actions (s <k>/r <rule>/a/<k>).
# $2: Reduce function hook
#   This function can access `rule=(LHS RHS1 RHS2 ...)`.
#   This function can access the RHS(i+1)'s content': `${contents[$((s + i))]}`.
#   This function should store the reduce result to `contents[$s]`.
# $3: Error handler function hook
#   Args passed to this function:
#     $1: Line
#     $2: Column
#     $3: Default error message
# $4: (optional) If set, enable debug.
# shellcheck disable=SC2030 # Modification to `contents` and `rule` are local.
bpt.__lr_parse() (
    local -rn table="$1"
    local -r reduce_fn="${2:-echo}"
    local -r error_fn="${3:-bpt.__error}"
    if [[ -n $4 ]]; then local -r NDEBUG=false; else local -r NDEBUG=true; fi

    # 20 should be enough ...
    # I assume no one's writing a BNF with more than 20 RHSs ...
    local -a STATE_PTRN=('')
    for i in {1..20}; do STATE_PTRN[i]="${STATE_PTRN[i - 1]}:*"; done

    # Parse stack
    #   Using string manipulation for states is faster than using an array.
    local states=':0' stack_size=1
    # Contents stack associatied wit the parse stack
    #   Large dict indexing is significantly faster than a regular one.
    #   Thus we use stack_size + associative array to emulate a regular array.
    local -A contents=([0]='')

    # Current reduction rule
    local -a rule=()
    # Current look-ahead token and its content
    local token='' content='' action=''
    # Location tracking variables
    local num_lines=0 num_bytes=0
    # Temporary variables
    local i=0 str_lines=0 buffer=''

    # $1: Goto state after shift
    bpt.__shift() {
        states+=":$1"
        contents["$stack_size"]="$content"
        ((++stack_size))
        token='' content=''
    }

    # $1: Rule
    bpt.__reduce() {
        # Although not robust, word splitting is faster than `read`
        # shellcheck disable=SC2206
        local num_rhs=$((${#rule[@]} - 1))

        # Reduce and goto state
        # shellcheck disable=SC2295
        states="${states%${STATE_PTRN[$num_rhs]}}"
        states+=":${table["${states##*:},${rule[0]}"]}"

        # Reduction start location (on the contents stack)
        local s=$((stack_size - num_rhs))

        # Run reduce hook (which saves the reduce result to `contents[$s]`)
        $reduce_fn || exit 1
        stack_size=$((s + 1))
    }

    # Simply print the result
    bpt.__accept() {
        printf '%s' "${contents[1]}"
    }

    # Default error handler
    bpt.__error() {
        echo "Error: Line $(($1 + 1)) Column $(($2 + 1))"
        echo "$3"
    } >&2

    # Debugging support
    $NDEBUG || {
        eval __orig_"$(declare -f bpt.__shift)"
        eval __orig_"$(declare -f bpt.__reduce)"
        eval __orig_"$(declare -f bpt.__accept)"
        bpt.__shift() {
            echo "[DBG] ${states##*:} Shift $1 \`$content\`" >&2
            __orig_bpt.__shift "$@"
        }
        bpt.__reduce() {
            echo "[DBG] ${states##*:} Reduce ${rule[*]}" >&2
            __orig_bpt.__reduce
        }
        bpt.__accept() {
            $NDEBUG || echo "[DBG] Result accepted" >&2
            __orig_bpt.__accept
        }
    }

    while true; do
        [[ -n $token ]] || {
            read -r token str_lines num_lines num_bytes
            IFS= read -r buffer || return 1
            content="$buffer"
            for ((i = 1; i < str_lines; ++i)); do
                IFS= read -r buffer || return 1
                content+=$'\n'"$buffer"
            done
        }

        action="${table["${states##*:},$token"]}"
        case "$action" in
        # Shift
        s*) bpt.__shift "${action#s }" ;;
        # Reduce
        r*) # shellcheck disable=SC2206
            rule=(${action#r })
            bpt.__reduce
            ;;
        # Accept
        a) bpt.__accept && break ;;
        # Error
        '')
            local expects='' rule_key=''
            for rule_key in "${!table[@]}"; do
                [[ $rule_key != "${states##*:},"* ||
                    -z "${table["$rule_key"]}" ||
                    "${table["$rule_key"]}" =~ ^[[:digit:]]+$ ]] ||
                    expects+="${expects:+,}${BPT_PP_TOKEN_TABLE["${rule_key##*,}"]:-${rule_key##*,}}"
            done
            $error_fn "$num_lines" "$num_bytes" \
                "Expecting \`${expects[*]}\` but got \`${token}\` ($content)."
            $NDEBUG || echo "[DBG] PARSER STATES ${states} TOKEN ${token} CONTENT ${content}." >&2
            exit 1
            ;;
        *) # Parse table error (internal error)
            echo "Internal error: STATES ${states} TOKEN ${token} CONTENT ${content}. " >&2
            echo "Internal error: Action '$action' not recognized." >&2
            exit 1
            ;;
        esac
    done
)

# The tokenizer for bpt
# $1: Left deilmiter
# $2: Right delimiter
# $3: Error handler function hook
#   Args passed to this function:
#     $1: Line
#     $2: Column
#     $3: Default error message
#
# Terminal token name to content mappings:
#   str: Anything outside the toplevel `ld ... rd` or
#        Anything inside `"..."` or `'...'` within any `ld ... rd`
#     Note1: `"` inside `"..."` needs to be escaped using `\"`,
#            and the same for `'` inside `'...'`.
#
#   ld: ${ldelim}   rd: ${rdelim}       lp: (           rp: )
#   cl: :           ex: !               eq: -eq         ne: -ne
#   lt: -lt         gt: -gt             le: -le         ge: -ge
#   streq: ==       strne: !=           strlt: <        strgt: >
#   strcm: =~
#   and|or|if|elif|else|for|in|include|quote: <as is>
#   id: [[:alpha:]_][[:alnum:]_]*
#
# shellcheck disable=SC2030
bpt.scan() (
    local -r ld="$1" rd="$2" error_fn="${3:-bpt.__scan_error}"
    bpt.__test_delims "$ld" "$rd" || return 1

    # Default error handler
    bpt.__scan_error() {
        echo "Error: Line $(($1 + 1)) Column $(($2 + 1))"
        echo "$3"
    } >&2

    # See man regex.7. We need to escape the meta characters of POSIX regex.
    local -rA ESC=(
        ['^']=\\ ['.']=\\ ['[']=\\ ['$']=\\ ['(']=\\ [')']=\\
        ['|']=\\ ['*']=\\ ['+']=\\ ['?']=\\ ['{']=\\ [\\]=\\
    )
    local e_ld='' e_rd='' i=0
    for ((i = 0; i < ${#ld}; ++i)); do e_ld+="${ESC["${ld:i:1}"]}${ld:i:1}"; done
    for ((i = 0; i < ${#rd}; ++i)); do e_rd+="${ESC["${rd:i:1}"]}${rd:i:1}"; done

    local -a KW=( # Keywords
        ':-' ':\+' ':\?' '##' '#' '%%' '%' '\^\^' '\^' ',,' ','
        '==' '!=' '=~' '>' '<' ':' '\!' '"' "'" '\(' '\)'
    )
    local -a SKW=( # Keywords ending with an alphanumeric character
        '-eq' '-ne' '-gt' '-lt' '-ge' '-le'
        'and' 'or' 'if' 'elif' 'else' 'for' 'in' 'include' 'quote'
    )
    if [[ "$e_ld" =~ [[:alnum:]_]$ ]]; then SKW+=("$e_ld"); else KW+=("$e_ld"); fi
    if [[ "$e_rd" =~ [[:alnum:]_]$ ]]; then SKW+=("$e_rd"); else KW+=("$e_rd"); fi
    local -r KW_RE="$(IFS='|' && echo -n "${KW[*]}")"
    local -r SKW_RE="$(IFS='|' && echo -n "${SKW[*]}")"
    local -r ID_RE='[[:alpha:]_][[:alnum:]_]*'

    # Scanner states
    local num_ld=0
    local quote=''

    # Location trackers
    local num_lines=0
    local num_bytes=0

    # String processing tracker & buffer.
    # `str_lines=''` means currently outside the scope of string
    local string='' str_lines='' str_bytes=''
    # Start scannign string
    bpt.__start_string() {
        str_lines="${str_lines:-1}"
        str_bytes="${str_bytes:-$num_bytes}"
    }
    # Commit (possibly multiline) string buffer
    # shellcheck disable=SC2031
    bpt.__commit_string() {
        ((str_lines > 0)) || return
        echo "str $str_lines $((num_lines + 1 - str_lines)) $str_bytes"
        # `$content` can be a literal `-ne`. Thus printf is needed.
        printf '%s\n' "$string"
        string='' str_lines='' str_bytes=''
    }

    # Tokenizer
    local line='' content='' newline=true
    bpt.__start_string
    while IFS= read -r line || { newline=false && false; } || [[ $line ]]; do
        # Scan the line
        while [[ -n "$line" ]]; do
            content='' # The consumed content (to be removed from `line`)
            if [[ $num_ld -eq 0 ]]; then
                # Outside `ld ... rd`
                if [[ $line =~ ^(${e_ld}) ]]; then
                    # If met `ld`, enter `ld ... rd`
                    bpt.__commit_string
                    ((++num_ld))
                    content="${BASH_REMATCH[1]}"
                    echo "ld 1 $num_lines $num_bytes"
                    printf '%s\n' "$content"
                elif [[ $line =~ (${e_ld}) ]]; then
                    content="${line%%"${BASH_REMATCH[1]}"*}"
                    string+="$content"
                else
                    content="$line"
                    string+="$line"
                fi
            elif [[ -n "$quote" ]]; then
                # Inside quotes in `ld ... rd`
                # Scan for `str` until we find a non-escaped quote.
                local line_copy="$line"
                while [[ $line_copy =~ ^[^${quote}]*\\${quote} ]]; do
                    # Escape quote inside string
                    string+="${line_copy%%"\\${quote}"*}${quote}"
                    content+="${line_copy%%"\\${quote}"*}\\${quote}"
                    line_copy="${line_copy#"${BASH_REMATCH[0]}"}"
                done

                if [[ $line_copy =~ ${quote} ]]; then
                    # Remove the closing quote from line
                    content+="${line_copy%%"${quote}"*}${quote}"
                    string+="${line_copy%%"${quote}"*}"
                    quote=''
                    bpt.__commit_string
                else
                    content="$line_copy"
                    string+="$line_copy"
                fi
            else
                # Non-strings. Commit string first.
                bpt.__commit_string
                if [[ $line =~ ^(${KW_RE}) ||
                    $line =~ ^(${SKW_RE})($|[^[:alnum:]_]) ]]; then
                    # Inside `ld ... rd` and matches a keyword at front
                    content="${BASH_REMATCH[1]}"
                    case "$content" in
                    '-eq') echo -n eq ;; '-ne') echo -n ne ;;
                    '-lt') echo -n lt ;; '-gt') echo -n gt ;;
                    '-le') echo -n le ;; '-ge') echo -n ge ;;
                    '==') echo -n streq ;; '!=') echo -n strne ;;
                    '>') echo -n strgt ;; '<') echo -n strlt ;;
                    '=~') echo -n strcm ;; ':?') echo -n err ;;
                    ':-') echo -n or ;; ':+') echo -n and ;;
                    '##') echo -n ppfx ;; '#') echo -n pfx ;;
                    '%%') echo -n ssfx ;; '%') echo -n sfx ;;
                    '^^') echo -n uupp ;; '^') echo -n upp ;;
                    ',,') echo -n llow ;; ',') echo -n low ;;
                    '!') echo -n ex ;; ':') echo -n cl ;;
                    '(') echo -n lp ;; ')') echo -n rp ;;
                    and | or | if | elif | else) ;&
                    for | in | include | quote) echo -n "$content" ;;
                    '"' | "'")
                        quote="$content"
                        bpt.__start_string
                        ;;
                    "$ld")
                        ((++num_ld))
                        echo -n ld
                        ;;
                    "$rd")
                        ((num_ld-- > 0)) || {
                            $error_fn "$num_lines" "$num_bytes" "Extra '$rd'."
                            return 1
                        }
                        ((num_ld != 0)) || bpt.__start_string
                        echo -n rd
                        ;;
                    *)
                        $error_fn "$num_lines" "$num_bytes" \
                            "Internal error: Unrecognized token ${content}"
                        return 1
                        ;;
                    esac
                    [[ -n $quote ]] || {
                        echo " 1 $num_lines $num_bytes"
                        printf '%s\n' "$content"
                    }
                else # Inside `ld ... rd` but outside quotes
                    # Ignore spaces inside `ld ... rd`
                    [[ ! $line =~ ^([[:space:]]+)(.*) ]] || {
                        line="${BASH_REMATCH[2]}"
                        ((num_bytes += ${#BASH_REMATCH[1]}))
                        continue
                    }
                    content="$line"

                    # Strip possible keywords suffixing variable names
                    ! [[ $content =~ (${KW_RE}) ||
                        $content =~ (${SKW_RE})($|[^[:alnum:]_]?) ]] ||
                        content="${content%%"${BASH_REMATCH[1]}"*}"

                    # Contents must be keywords
                    [[ $content =~ ^(${ID_RE}) ]] || {
                        $error_fn "$num_lines" "$num_bytes" \
                            "'$content' is not a valid identifier"
                        return 1
                    }
                    content="${BASH_REMATCH[1]}"
                    echo "id 1 $num_lines $num_bytes"
                    printf '%s\n' "$content"
                fi
            fi

            # Post-processing only counts the last line read.
            line="${line#"$content"}"
            ((num_bytes += ${#content}))
        done
        ((++num_lines))
        num_bytes=0 content=''

        # Decide whether currently scanning a string
        # Only count newlines in strings (outside `ld ... rd` and inside quotes).
        [[ $num_ld -gt 0 && -z "$quote" ]] || {
            bpt.__start_string
            ! $newline || { string+=$'\n' && ((++str_lines)); }
        }

        newline=true
    done
    bpt.__commit_string
    echo "$ 1 $num_lines 0" # The EOF token
    echo ''                 # The EOF content (empty)
)

bpt.__test_delims() {
    [[ $1 != *' '* && $2 != *' '* ]] || {
        echo "Left and right delimiters must not contain spaces." >&2
        return 1
    }
    [[ "$1" != "$2" ]] || {
        echo "Left and right delimiters must be different." >&2
        return 1
    }
}

# The reduce function to collect all variables
# shellcheck disable=SC2031 # Direct access of `rule` and `contents` for speed.
bpt.__reduce_collect_vars() {
    # For all `id` token, allow only the path via the VAR rule.
    # For all `str` token, allow only the path to the INCLUDE rule.
    case "${rule[0]}" in
    ID | STR) ;;
    STMT) [[ "${rule[1]}" != STR ]] || contents[$s]='' ;;
    VAR)
        contents[$s]="${contents[$((s + 1))]}"$'\n'
        [[ ${#rule[@]} -eq 4 || ${rule[4]} != VAR ]] ||
            contents[$s]+="${contents[$((s + 3))]}"
        ;;
    BUILTIN | QUOTE) contents[$s]="${contents[$((s + 3))]}" ;;
    INCLUDE) contents[$s]="$(bpt.__recursive_process "${contents[$((s + 3))]}")"$'\n' ;;
    FORIN) # Filter tokens defined by the FORIN rule
        contents[$s]="${contents[$((s + 4))]}"
        local var
        while read -r var; do
            [[ -z $var || $var == "${contents[$((s + 2))]}" ]] || contents[$s]+="$var"$'\n'
        done <<<"${contents[$((s + 6))]}"
        ;;
    *) # Prevent the propagation of all other non-terminals
        [[ "${#rule[@]}" -ne 1 ]] || { contents[$s]='' && return; }
        [[ "${rule[1]^^}" == "${rule[1]}" ]] || contents[$s]=''
        local i=1
        for (( ; i < ${#rule[@]}; ++i)); do
            [[ "${rule[i + 1],,}" == "${rule[i + 1]}" ]] ||
                contents[$s]+="${contents[$((s + i))]}"
        done
        ;;
    esac
}

# The reduce function to collect all includes
# shellcheck disable=SC2031
bpt.__reduce_collect_includes() {
    # For all `str` token, allow only the path via the INCLUDE rule.
    case "${rule[0]}" in
    STR) ;; # Allow the propagation of str
    STMT) [[ "${rule[1]}" != STR ]] || contents[$s]='' ;;
    VAR) contents[$s]='' ;;
    INCLUDE)
        contents[$s]="${contents[$((s + 3))]}"$'\n'
        contents[$s]+="$(bpt.__recursive_process "${contents[$((s + 3))]}")"
        ;;
    *) # Prevent the propagation of all other non-terminals
        [[ "${#rule[@]}" -ne 1 ]] || { contents[$s]='' && return; }
        [[ "${rule[1]^^}" == "${rule[1]}" ]] || contents[$s]=''
        local i=1
        for (( ; i < ${#rule[@]}; ++i)); do
            [[ "${rule[i + 1],,}" == "${rule[i + 1]}" ]] ||
                contents[$s]+="${contents[$((s + i))]}"
        done
        ;;
    esac
}

# The reduce function to generate the template
# shellcheck disable=SC2031
bpt.__reduce_generate() {
    case "${rule[0]}" in
    # Note: Since `contents[$s]` is exactly the first RHS, the
    #   `${contents[$s]}="${contents[$s]}"` assignment is unnecessary here.
    STR | UOP | BOP | MOD) ;;
    # Tag location for BUILTIN error reporting
    ID) contents[$s]+=":$num_lines:$num_bytes" ;;
    VAR) case "${#rule[@]}" in
        4) contents[$s]="\${${contents[$((s + 1))]%:*:*}}" ;;
        *)
            case "${contents[$((s + 2))]}" in
            or) contents[$s]="\${${contents[$((s + 1))]%:*:*}:-" ;;
            and) contents[$s]="\${${contents[$((s + 1))]%:*:*}:+" ;;
            *) contents[$s]="\${${contents[$((s + 1))]%:*:*}${contents[$((s + 2))]}" ;;
            esac
            case "${rule[4]}" in
            VAR) contents[$s]+="\$(e \"${contents[$((s + 3))]}\")}" ;;
            STR) contents[$s]+="\$(e ${contents[$((s + 3))]@Q})}" ;;
            rd) contents[$s]+='}' ;;
            esac
            ;;
        esac ;;
    ARGS)
        # Strip the tag from STMT
        local stmt_type='' stmt=
        case "${#rule[@]}" in
        2)
            stmt_type="${contents[$s]%%:*}"
            stmt="${contents[$s]#*:}"
            contents[$s]=''
            ;;
        3)
            stmt_type="${contents[$((s + 1))]%%:*}"
            stmt="${contents[$((s + 1))]#*:}"
            ;;
        esac

        # Note: `${stmt@Q}` is faster than `printf '%q' ${stmt}`
        case "$stmt_type" in
        STR) contents[$s]+=" ${stmt@Q} " ;;
        VAR | BUILTIN | QUOTE) contents[$s]+=" $stmt " ;;
        INCLUDE | FORIN | IF) contents[$s]+=" \"\$($stmt)\" " ;;
        esac
        ;;
    QUOTE) contents[$s]="\"\$(e ${contents[$((s + 3))]})\"" ;;
    BUILTIN) # Filter allowed builtints
        local builtin_name=${contents[$((s + 1))]%:*:*}
        case "$builtin_name" in
        len | seq | split) contents[$s]="\$($builtin_name ${contents[$((s + 3))]})" ;;
        cat) contents[$s]="\$(e ${contents[$((s + 3))]})" ;;
        *) # Extract and compute correct error location from ID
            local line_col="${contents[$((s + 1))]#"$builtin_name"}"
            local err_line=${line_col%:*} && err_line="${err_line:1}"
            local err_byte=$((${line_col##*:} - ${#builtin_name}))
            $error_fn "$err_line" "$err_byte" \
                "Error Unrecognized builtin function $builtin_name" >&2
            exit 1
            ;;
        esac
        ;;
    INCLUDE) contents[$s]="$(bpt.__recursive_process "${contents[$((s + 3))]}")" ;;
    FORIN) contents[$s]="for ${contents[$((s + 2))]%:*:*} in ${contents[$((s + 4))]}; do ${contents[$((s + 6))]} done" ;;
    BOOL) case "${#rule[@]}" in
        2) contents[$s]="\"\$(e ${contents[$s]})\"" ;;
        4) case "${contents[$((s + 1))]}" in # Don't quote the rhs of `=~`
            '=~') contents[$s]+=" ${contents[$((s + 1))]} \$(e ${contents[$((s + 2))]})" ;;
            *) contents[$s]+=" ${contents[$((s + 1))]} \"\$(e ${contents[$((s + 2))]})\"" ;;
            esac ;;
        esac ;;
    BOOLA) case "${#rule[@]}" in
        4) case "${rule[1]}" in
            BOOLA) contents[$s]="${contents[$s]} && ${contents[$((s + 2))]}" ;;
            lp) contents[$s]="( ${contents[$((s + 1))]} )" ;;
            esac ;;
        5) contents[$s]="${contents[$s]} && ${contents[$((s + 2))]} ${contents[$((s + 3))]}" ;;
        6) contents[$s]="${contents[$s]} && ( ${contents[$((s + 3))]} )" ;;
        7) contents[$s]="${contents[$s]} && ${contents[$((s + 2))]} ( ${contents[$((s + 4))]} )" ;;
        esac ;;
    BOOLO) case "${#rule[@]}" in
        4) contents[$s]="${contents[$s]} || ${contents[$((s + 2))]}" ;;
        5) contents[$s]="${contents[$s]} || ${contents[$((s + 2))]} ${contents[$((s + 3))]}" ;;
        esac ;;
    BOOLS) [[ ${#rule[@]} -eq 2 ]] || contents[$s]="${contents[$s]} ${contents[$((s + 1))]}" ;;
    ELSE) case "${#rule[@]}" in
        1) contents[$s]='' ;;
        *) contents[$s]="else ${contents[$((s + 2))]}" ;;
        esac ;;
    ELIF) case "${#rule[@]}" in
        1) contents[$s]='' ;;
        *) contents[$s]="${contents[$s]} elif [[ ${contents[$((s + 2))]} ]]; then ${contents[$((s + 4))]}" ;;
        esac ;;
    IF) case "${#rule[@]}" in
        9) contents[$s]="if [[ ${contents[$((s + 2))]} ]]; then ${contents[$((s + 4))]}${contents[$((s + 5))]}${contents[$((s + 6))]} fi" ;;
        8) contents[$s]="if [[ ${contents[$((s + 1))]} ]]; then ${contents[$((s + 3))]} else ${contents[$((s + 5))]} fi" ;;
        6) contents[$s]="if [[ ${contents[$((s + 1))]} ]]; then ${contents[$((s + 3))]} fi" ;;
        4) contents[$s]="if [[ ${contents[$((s + 1))]} ]]; then { e true; }; else { e false; }; fi" ;;
        esac ;;
    STMT)
        # Tag the sub-type to the reduce result
        # (Need to strip the tag wherever STMT is used)
        contents[$s]="${rule[1]}:${contents[$s]}"
        ;;
    DOC) # Similar to ARGS but produces commands instead of strings
        # Return when document is empty
        [[ "${#rule[@]}" -ne 1 ]] || { contents[$s]='' && return; }

        # Strip the tag from STMT
        local stmt_type="${contents[$((s + 1))]%%:*}"
        local stmt="${contents[$((s + 1))]#*:}"

        # Reduce the document
        case "$stmt_type" in
        STR) case "$stmt" in
            '') contents[$s]+=":;" ;;
            *) contents[$s]+="{ e ${stmt@Q}; };" ;;
            esac ;;
        QUOTE) contents[$s]+="{ e $stmt; };" ;;
        BUILTIN | VAR) contents[$s]+="{ e \"$stmt\"; };" ;;
        INCLUDE) contents[$s]+="$stmt" ;;
        FORIN | IF) contents[$s]+="{ $stmt; };" ;;
        esac
        ;;
    *) echo "Internal error: Rule ${rule[*]} not recognized" >&2 ;;
    esac
}

# Process the template
#
# $1: Left deilmiter
# $2: Right delimiter
# $3: The reduce function hook to pass to the parser.
#     Defaults to bpt.__reduce_collect_vars
# $4: File to process
# $5: (optional) If set, enable debug.
#
# Input: Template from stdin
#
# Grammar:
#   DOC     -> DOC STMT
#            | .
#   STMT    -> IF | FORIN | INCLUDE | BUILTIN | QUOTE | VAR | STR .
#   IF      -> ld if BOOLS cl DOC ELIF ELSE rd
#            | ld BOOLS cl DOC cl DOC rd
#            | ld BOOLS cl DOC rd
#            | ld BOOLS rd .
#   ELIF    -> ELIF elif BOOLS cl DOC
#            | .
#   ELSE    -> else cl DOC
#            | .
#   BOOLS   -> BOOLO
#            | UOP BOOLS .
#   BOOLO   -> BOOLO or BOOLA
#            | BOOLO or UOP BOOLA
#            | BOOLA .
#   BOOLA   -> BOOLA and BOOL
#            | BOOLA and UOP BOOL
#            | BOOLA and lp BOOLS rp
#            | BOOLA and UOP lp BOOLS rp
#            | lp BOOLS rp
#            | BOOL .
#   BOOL    -> ARGS BOP ARGS
#            | ARGS .
#   FORIN   -> ld for ID in ARGS cl DOC rd .
#   INCLUDE -> ld include cl STR rd .
#   BUILTIN -> ld ID cl ARGS rd .
#   QUOTE   -> ld quote cl ARGS rd .
#   ARGS    -> ARGS STMT
#            | STMT .
#   VAR     -> ld ID rd
#            | ld ID MOD rd
#            | ld ID MOD VAR rd
#            | ld ID MOD STR rd .
#   MOD     -> and   | or    | err
#            | pfx   | ppfx  | sfx   | ssfx
#            | upp   | uupp  | low   | llow  .
#   BOP     -> ne    | eq    | gt    | lt    | ge    | le
#            | strne | streq | strgt | strlt | strcm .
#   UOP     -> ex .
#   ID      -> id .
#   STR     -> str .
#
# Note1: the combination of BOOLO and BOOLA is equivalent to the expression
#   grammar `BOOLS -> BOOL or BOOL | BOOL and BOOL | lp BOOL rp | BOOL .`
#   with left associativity for `and` and `or` meanwhile `and` having higher
#   precidence than `or`. (Solves shift-reduce conflict with subclassing).
# See: https://ece.uwaterloo.ca/~vganesh/TEACHING/W2014/lectures/lecture08.pdf
#
# Note2: the `ID -> id` and `STR -> str` rules are not redundant.
#   They are for better controls when hooking the reduce function.
bpt.process() (
    local -r ld="$1" rd="$2" file="$4" debug="$5"
    local -r reduce_fn="${3:-bpt.__reduce_generate}"
    local -a file_stack=("${file_stack[@]}")

    [[ -f $file ]] || {
        echo "Error: file '$file' does not exist" >&2
        return 1
    }
    file_stack+=("$file")

    # Curry this function so that it can be called by the reducer recursively
    bpt.__recursive_process() {
        local file
        # Detect recursive includes
        for file in "${file_stack[@]}"; do
            [[ $file -ef $1 ]] && {
                printf "Error: cyclic include detected:\n"
                printf '  In: %s\n' "${file_stack[0]}"
                printf '  --> %s\n' "${file_stack[@]:1}"
                printf '  --> %s\n' "${file}"
                return 1
            } >&2
        done
        bpt.process "$ld" "$rd" "$reduce_fn" "$1" "$debug"
    }

    # Pretty-print parse errors
    bpt.__error_handler() {
        echo "Error: File '$file' Line $(($1 + 1)) Column $(($2 + 1))"
        echo "$3"
        echo
        # Pretty-print the error location
        local -a line=()
        mapfile -t -s "$1" -n 1 line <"$file"
        echo "${line[0]}"
        printf "%$2s^--- \033[1mHERE\033[0m\n"
    } >&2

    # Prase with the provided reduce function
    bpt.__lr_parse __BPT_PARSE_TABLE "$reduce_fn" bpt.__error_handler "$debug" \
        < <(bpt.scan "$ld" "$rd" bpt.__error_handler <"$file")
)

# $1: Left deilmiter
# $2: Right delimiter
# $3: File to process
# $4: (optional) If set, enable debug.
# shellcheck disable=SC2207
bpt.fingerprint() {
    local -r ld="$1" rd="$2" file="$3" debug="$4"

    # Collect vars and includes
    local -a vars=() incs=()
    local var_list inc_list
    var_list="$(bpt.process "$ld" "$rd" bpt.__reduce_collect_vars "$file" "$debug")" || exit 1
    var_list="$(bpt.__dedup "$var_list")"
    [[ -z $var_list ]] || mapfile -t vars <<<"$var_list"
    inc_list="$(bpt.process "$ld" "$rd" bpt.__reduce_collect_includes "$file" "$debug")" || exit 1
    inc_list="$(bpt.__dedup "$inc_list")"
    [[ -z $inc_list ]] || mapfile -t incs <<<"$inc_list"
    local fingerprint=''
    local -a md5=()

    # Hash this script (the generator)
    md5=($(md5sum "${BASH_SOURCE[0]}")) && fingerprint+="M:${md5[0]}"

    # Hash the file itself
    md5=($(md5sum "$file")) && fingerprint+=":S:${md5[0]}"

    # Digest the includes
    for inc in "${incs[@]}"; do
        md5=($(md5sum "$inc")) && fingerprint+=":I:${md5[0]}"
    done
    # Digest and check for missing vars
    for var in "${vars[@]}"; do
        [[ ${!var+.} ]] || {
            echo "Error: variable '$var' is required but not set" >&2
            return 1
        }
        md5=($(echo -n "${var}${!var}" | md5sum)) && fingerprint+=":V:${md5[0]}"
    done

    # Digest the digests
    [[ $debug ]] && echo "[DBG] Raw fingerprint: $fingerprint"
    md5=($(echo -n "${fingerprint}" | md5sum)) && fingerprint="${md5[0]}"
    echo "$fingerprint"
}

bpt.print_help() {
    echo -e "\033[1mbpt - A command-line tool for processing simple templates\033[0m"
    echo
    echo -e "\033[1mSYNOPSIS\033[0m"
    echo "  bpt <command> [-l <LEFT_DELIMITER>] [-r <RIGHT_DELIMITER>] [-d] [<FILENAME>]"
    echo
    echo -e "\033[1mCOMMANDS\033[0m"
    echo "  scan, s:"
    echo "    Call the scanner (lexer)."
    echo
    echo "  generate, g:"
    echo "    Generate a shell script based on the input file. Output is sent to stdout."
    echo
    echo "  generate-eval, ge:"
    echo "    Same as generate, but the output is evaluated. Output is sent to stdout."
    echo
    echo "  collect-vars, cv:"
    echo "    Collect variable used in the input file recursively and output them to stdout."
    echo
    echo "  collect-includes, ci:"
    echo "    Collect all files included in the input file recursively and output them to stdout."
    echo
    echo "  fingerprint, f:"
    echo "    Generate a unique identifier based on all factors affecting the evaluation output."
    echo
    echo "  -h, --help:"
    echo "    Print this help."
    echo
    echo "  -v, --version:"
    echo "    Print version number."
    echo
    echo -e "\033[1mOPTIONS\033[0m"
    echo "  -l <LEFT_DELIMITER>, --left-delimiter <LEFT_DELIMITER>:"
    echo "    Set the left delimiter to use for placeholders (default \`{{\`)."
    echo
    echo "  -r <RIGHT_DELIMITER>, --right-delimiter <RIGHT_DELIMITER>:"
    echo "    Set the right delimiter to use for placeholders (default \`}}\`)."
    echo
    echo "  -d, --debug:"
    echo "    Enable debug mode."
    echo
    echo -e "\033[1mARGUMENTS\033[0m"
    echo "   bpt takes an optional input file path as its argument. If no input file is specified, bpt will read from stdin."
    echo
    echo -e "\033[1mEXAMPLES\033[0m"
    echo "  Generate script from a single input file using default delimiters:"
    echo "    bpt g input.tpl > output.sh"
    echo
    echo "  Render the input file:"
    echo "    var1=VAR1 var2=VAR2 ... bpt ge input.tpl"
    echo
    echo "  Collect variable names and values from an input file:"
    echo "    bpt cv input.tpl"
    echo
    echo "  Collect include file paths from an input file:"
    echo "    bpt ci input.tpl"
    echo
    echo "  Generate a fingerprint for an input"
    echo "    var1=VAR1 var2=VAR2 ... bpt f input.tpl"
    echo
    echo "  Using custom delimiters:"
    echo "    bpt -l \"<<\" -r \">>\" g input.tpl > output.sh"
    echo
    echo -e "\033[1mTEMPLATE GRAMMAR EXAMPLES\033[0m"
    echo "  Variable modding"
    echo '    {{ var }}'
    echo '    {{ var or "abc" }}'
    echo '    {{ var %% {{var2}} }}'
    echo
    echo '    Available modifiers are: '
    echo '      replacement: and or :- :+ '
    echo '      non-empty:   :?'
    echo '      pre/suf-fix: ##  #  %%  %'
    echo '      upper/lower: ^^  ^  ,,  ,'
    echo
    echo "  Branching"
    echo '    {{ {{x}}: {{var1}} : {{var2}} }}'
    echo '    {{ if {{x}}: {{var1}} else : {{var2}} }}'
    echo '    {{ if {{x}} -gt "5": {{var1}} elif: {{var2}} else: {{var3}} }}'
    echo '    {{ if ({{var1}} > "abc" and {{var2}} < "def") or {{var3}} == "hello" : {{ include : "input2.tpl" }} }}'
    echo
    echo "    Available operators are: "
    echo "      compare numbers:   -ne, -eq, -gt, -lt, -ge, -le "
    echo "      compare strings:   >, <, ==, !=, =~"
    echo "      logical operators: and, or, !"
    echo "      grouping:          ()"
    echo
    echo "  Iterate a list"
    echo '    {{ for {{i}} in "a" "b" "c": "abc"{{i}}"def" }}'
    echo '    {{ for {{i}} in {{seq: "5"}}: "abc"{{i}}"def" }}'
    echo
    echo "  Include another template"
    echo '    {{ include : "input2.tpl" }}'
    echo
    echo "  Builtin functions"
    echo '    {{ seq: "5" }}'
    echo '    {{ len: "abc" }}'
    echo '    {{ cat: "1" "2" "3" }}'
    echo '    {{ quote: {{seq: "1" "2" "5"}} }}'
    echo '    {{ split: "1 2 3" }}'
    echo
    echo "  Note: bpt doesn't distinguish between strings and numbers."
    echo "    All non-keywords should be treated as strings."
    echo "    All strings inside {{...}} need to be quoted. e.g. 'abc', \"abc\", '123'."
    echo
    echo -e "\033[1mCOPYRIGHT\033[0m"
    echo "  MIT License."
    echo "  Copyright (c) 2023-2024 Hu Sixu."
    echo "  https://github.com/husixu1/bpt"
}

bpt.__clean_env() {
    # Clean the environment to avoid builtin overrides
    # See https://unix.stackexchange.com/questions/188327
    POSIXLY_CORRECT=1
    \unset -f help read unset
    \unset POSIXLY_CORRECT
    while \read -r cmd; do
        [[ "$cmd" =~ ^([a-z:.\[]+): ]] && \unset -f "${BASH_REMATCH[1]}"
    done < <(\help -s "*")
    declare -rg __BPT_ENV_CLEANED=1
}

bpt.main() { (
    [[ $__BPT_ENV_CLEANED ]] || bpt.__clean_env # Clean the environment once
    local ld='{{' rd='}}'
    local infile=''
    local cmd='' reduce_fn=bpt.__reduce_generate post_process=eval
    local debug=''

    # Parse command
    case "$1" in
    scan | s) cmd=scan ;;
    generate | g)
        cmd=generate
        reduce_fn=bpt.__reduce_generate
        post_process='echo'
        ;;
    generate-eval | ge)
        cmd=generate-eval
        reduce_fn=bpt.__reduce_generate
        post_process='eval'
        ;;
    collect-vars | cv)
        cmd=collect-vars
        reduce_fn=bpt.__reduce_collect_vars
        post_process=bpt.__dedup
        ;;
    collect-includes | ci)
        cmd=collect-includes
        reduce_fn=bpt.__reduce_collect_includes
        post_process=bpt.__dedup
        ;;
    fingerprint | f)
        cmd=fingerprint
        ;;
    -v | --version) echo "$__BPT_VERSION" && exit 0 ;;
    -h | --help | '') bpt.print_help && exit 0 ;;
    *)
        echo "Unrecognized command '$1'" >&2
        bpt.print_help
        exit 1
        ;;
    esac
    shift

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -l | --left-delimiter) shift && ld="$1" ;;
        -r | --right-delimiter) shift && rd="$1" ;;
        -d | --debug) debug=1 ;;
        -h | --help)
            bpt.print_help
            exit 0
            ;;
        *)
            [[ -z $infile ]] || {
                echo "Error: Option '$1' not recognized." >&2
                bpt.print_help
                return 1
            }
            infile="$1"
            ;;
        esac
        shift
    done

    # If file not provided, read into a temporary file and use that file.
    [[ -n $infile ]] || {
        infile="$(mktemp)" || { echo "Error: mktemp failed." >&2 && exit 1; }
        # shellcheck disable=SC2064
        trap "rm -f -- \"${infile:?}\"; trap - RETURN" RETURN
        cat >"${infile:?}"
    }

    # Global constants for pretty-printing
    local -rA BPT_PP_TOKEN_TABLE=(
        [ld]="$ld" [rd]="$rd"
        [eq]='-eq' [ne]='-ne' [gt]='-gt' [lt]='-lt' [ge]='-ge' [le]='-le'
        [streq]='==' [strne]='!=' [strgt]='>' [strlt]='<'
        [cl]=':' [ex]='!' [lp]='(' [rp]=')')

    # Deduplication function for collect-{var,include}
    bpt.__dedup() { echo -n "$1" | sort | uniq; }

    # Append this if reducer is bpt.__reduce_generate
    local HEADER=''
    [[ $reduce_fn != bpt.__reduce_generate ]] || {
        read -r -d '' HEADER <<-'EOF'
#!/bin/bash
\unset -f echo printf || true
e(){ printf '%s' "$@"; };
len(){ e "${#1}"; };
seq(){ command seq -s ' ' -- "$@" || kill $__BPT_BASHPID; };
split(){ e "$*"; };
EOF
        HEADER+=$'\n'
    }

    # Execute command
    case "$cmd" in
    scan) bpt.scan "$ld" "$rd" <"$infile" ;;
    fingerprint) bpt.fingerprint "$ld" "$rd" "$infile" "$debug" ;;
    *) result="$(bpt.process "$ld" "$rd" "$reduce_fn" "$infile" "$debug")" &&
        (__BPT_BASHPID=$BASHPID && $post_process "$HEADER$result" || return $?) ;;
    esac
) }

# shellcheck disable=SC2034
# >>> BPT_PARSE_TABLE_S >>>
readonly -A __BPT_PARSE_TABLE=( # {{{
    ["0,ld"]="r DOC" ["0,str"]="r DOC" ["0,$"]="r DOC" ["0,DOC"]="1" ["1,ld"]="s 10"
    ["1,str"]="s 11" ["1,$"]="a" ["1,STMT"]="2" ["1,IF"]="3" ["1,FORIN"]="4"
    ["1,INCLUDE"]="5" ["1,BUILTIN"]="6" ["1,QUOTE"]="7" ["1,VAR"]="8" ["1,STR"]="9"
    ["2,ld"]="r DOC DOC STMT" ["2,cl"]="r DOC DOC STMT" ["2,rd"]="r DOC DOC STMT"
    ["2,elif"]="r DOC DOC STMT" ["2,else"]="r DOC DOC STMT"
    ["2,str"]="r DOC DOC STMT" ["2,$"]="r DOC DOC STMT" ["3,ld"]="r STMT IF"
    ["3,cl"]="r STMT IF" ["3,rd"]="r STMT IF" ["3,elif"]="r STMT IF"
    ["3,else"]="r STMT IF" ["3,or"]="r STMT IF" ["3,and"]="r STMT IF"
    ["3,rp"]="r STMT IF" ["3,ne"]="r STMT IF" ["3,eq"]="r STMT IF"
    ["3,gt"]="r STMT IF" ["3,lt"]="r STMT IF" ["3,ge"]="r STMT IF"
    ["3,le"]="r STMT IF" ["3,strne"]="r STMT IF" ["3,streq"]="r STMT IF"
    ["3,strgt"]="r STMT IF" ["3,strlt"]="r STMT IF" ["3,strcm"]="r STMT IF"
    ["3,str"]="r STMT IF" ["3,$"]="r STMT IF" ["4,ld"]="r STMT FORIN"
    ["4,cl"]="r STMT FORIN" ["4,rd"]="r STMT FORIN" ["4,elif"]="r STMT FORIN"
    ["4,else"]="r STMT FORIN" ["4,or"]="r STMT FORIN" ["4,and"]="r STMT FORIN"
    ["4,rp"]="r STMT FORIN" ["4,ne"]="r STMT FORIN" ["4,eq"]="r STMT FORIN"
    ["4,gt"]="r STMT FORIN" ["4,lt"]="r STMT FORIN" ["4,ge"]="r STMT FORIN"
    ["4,le"]="r STMT FORIN" ["4,strne"]="r STMT FORIN" ["4,streq"]="r STMT FORIN"
    ["4,strgt"]="r STMT FORIN" ["4,strlt"]="r STMT FORIN" ["4,strcm"]="r STMT FORIN"
    ["4,str"]="r STMT FORIN" ["4,$"]="r STMT FORIN" ["5,ld"]="r STMT INCLUDE"
    ["5,cl"]="r STMT INCLUDE" ["5,rd"]="r STMT INCLUDE" ["5,elif"]="r STMT INCLUDE"
    ["5,else"]="r STMT INCLUDE" ["5,or"]="r STMT INCLUDE" ["5,and"]="r STMT INCLUDE"
    ["5,rp"]="r STMT INCLUDE" ["5,ne"]="r STMT INCLUDE" ["5,eq"]="r STMT INCLUDE"
    ["5,gt"]="r STMT INCLUDE" ["5,lt"]="r STMT INCLUDE" ["5,ge"]="r STMT INCLUDE"
    ["5,le"]="r STMT INCLUDE" ["5,strne"]="r STMT INCLUDE"
    ["5,streq"]="r STMT INCLUDE" ["5,strgt"]="r STMT INCLUDE"
    ["5,strlt"]="r STMT INCLUDE" ["5,strcm"]="r STMT INCLUDE"
    ["5,str"]="r STMT INCLUDE" ["5,$"]="r STMT INCLUDE" ["6,ld"]="r STMT BUILTIN"
    ["6,cl"]="r STMT BUILTIN" ["6,rd"]="r STMT BUILTIN" ["6,elif"]="r STMT BUILTIN"
    ["6,else"]="r STMT BUILTIN" ["6,or"]="r STMT BUILTIN" ["6,and"]="r STMT BUILTIN"
    ["6,rp"]="r STMT BUILTIN" ["6,ne"]="r STMT BUILTIN" ["6,eq"]="r STMT BUILTIN"
    ["6,gt"]="r STMT BUILTIN" ["6,lt"]="r STMT BUILTIN" ["6,ge"]="r STMT BUILTIN"
    ["6,le"]="r STMT BUILTIN" ["6,strne"]="r STMT BUILTIN"
    ["6,streq"]="r STMT BUILTIN" ["6,strgt"]="r STMT BUILTIN"
    ["6,strlt"]="r STMT BUILTIN" ["6,strcm"]="r STMT BUILTIN"
    ["6,str"]="r STMT BUILTIN" ["6,$"]="r STMT BUILTIN" ["7,ld"]="r STMT QUOTE"
    ["7,cl"]="r STMT QUOTE" ["7,rd"]="r STMT QUOTE" ["7,elif"]="r STMT QUOTE"
    ["7,else"]="r STMT QUOTE" ["7,or"]="r STMT QUOTE" ["7,and"]="r STMT QUOTE"
    ["7,rp"]="r STMT QUOTE" ["7,ne"]="r STMT QUOTE" ["7,eq"]="r STMT QUOTE"
    ["7,gt"]="r STMT QUOTE" ["7,lt"]="r STMT QUOTE" ["7,ge"]="r STMT QUOTE"
    ["7,le"]="r STMT QUOTE" ["7,strne"]="r STMT QUOTE" ["7,streq"]="r STMT QUOTE"
    ["7,strgt"]="r STMT QUOTE" ["7,strlt"]="r STMT QUOTE" ["7,strcm"]="r STMT QUOTE"
    ["7,str"]="r STMT QUOTE" ["7,$"]="r STMT QUOTE" ["8,ld"]="r STMT VAR"
    ["8,cl"]="r STMT VAR" ["8,rd"]="r STMT VAR" ["8,elif"]="r STMT VAR"
    ["8,else"]="r STMT VAR" ["8,or"]="r STMT VAR" ["8,and"]="r STMT VAR"
    ["8,rp"]="r STMT VAR" ["8,ne"]="r STMT VAR" ["8,eq"]="r STMT VAR"
    ["8,gt"]="r STMT VAR" ["8,lt"]="r STMT VAR" ["8,ge"]="r STMT VAR"
    ["8,le"]="r STMT VAR" ["8,strne"]="r STMT VAR" ["8,streq"]="r STMT VAR"
    ["8,strgt"]="r STMT VAR" ["8,strlt"]="r STMT VAR" ["8,strcm"]="r STMT VAR"
    ["8,str"]="r STMT VAR" ["8,$"]="r STMT VAR" ["9,ld"]="r STMT STR"
    ["9,cl"]="r STMT STR" ["9,rd"]="r STMT STR" ["9,elif"]="r STMT STR"
    ["9,else"]="r STMT STR" ["9,or"]="r STMT STR" ["9,and"]="r STMT STR"
    ["9,rp"]="r STMT STR" ["9,ne"]="r STMT STR" ["9,eq"]="r STMT STR"
    ["9,gt"]="r STMT STR" ["9,lt"]="r STMT STR" ["9,ge"]="r STMT STR"
    ["9,le"]="r STMT STR" ["9,strne"]="r STMT STR" ["9,streq"]="r STMT STR"
    ["9,strgt"]="r STMT STR" ["9,strlt"]="r STMT STR" ["9,strcm"]="r STMT STR"
    ["9,str"]="r STMT STR" ["9,$"]="r STMT STR" ["10,ld"]="s 10" ["10,if"]="s 12"
    ["10,lp"]="s 23" ["10,for"]="s 14" ["10,include"]="s 15" ["10,quote"]="s 17"
    ["10,ex"]="s 22" ["10,id"]="s 20" ["10,str"]="s 11" ["10,STMT"]="26"
    ["10,IF"]="3" ["10,FORIN"]="4" ["10,INCLUDE"]="5" ["10,BUILTIN"]="6"
    ["10,QUOTE"]="7" ["10,VAR"]="8" ["10,STR"]="9" ["10,BOOLS"]="13"
    ["10,BOOLO"]="18" ["10,UOP"]="19" ["10,BOOLA"]="21" ["10,BOOL"]="24"
    ["10,ARGS"]="25" ["10,ID"]="16" ["11,ld"]="r STR str" ["11,cl"]="r STR str"
    ["11,rd"]="r STR str" ["11,elif"]="r STR str" ["11,else"]="r STR str"
    ["11,or"]="r STR str" ["11,and"]="r STR str" ["11,rp"]="r STR str"
    ["11,ne"]="r STR str" ["11,eq"]="r STR str" ["11,gt"]="r STR str"
    ["11,lt"]="r STR str" ["11,ge"]="r STR str" ["11,le"]="r STR str"
    ["11,strne"]="r STR str" ["11,streq"]="r STR str" ["11,strgt"]="r STR str"
    ["11,strlt"]="r STR str" ["11,strcm"]="r STR str" ["11,str"]="r STR str"
    ["11,$"]="r STR str" ["12,ld"]="s 10" ["12,lp"]="s 23" ["12,ex"]="s 22"
    ["12,str"]="s 11" ["12,STMT"]="26" ["12,IF"]="3" ["12,FORIN"]="4"
    ["12,INCLUDE"]="5" ["12,BUILTIN"]="6" ["12,QUOTE"]="7" ["12,VAR"]="8"
    ["12,STR"]="9" ["12,BOOLS"]="27" ["12,BOOLO"]="18" ["12,UOP"]="19"
    ["12,BOOLA"]="21" ["12,BOOL"]="24" ["12,ARGS"]="25" ["13,cl"]="s 28"
    ["13,rd"]="s 29" ["14,id"]="s 20" ["14,ID"]="30" ["15,cl"]="s 31"
    ["16,cl"]="s 32" ["16,rd"]="s 33" ["16,or"]="s 36" ["16,and"]="s 35"
    ["16,err"]="s 37" ["16,pfx"]="s 38" ["16,ppfx"]="s 39" ["16,sfx"]="s 40"
    ["16,ssfx"]="s 41" ["16,upp"]="s 42" ["16,uupp"]="s 43" ["16,low"]="s 44"
    ["16,llow"]="s 45" ["16,MOD"]="34" ["17,cl"]="s 46" ["18,cl"]="r BOOLS BOOLO"
    ["18,rd"]="r BOOLS BOOLO" ["18,or"]="s 47" ["18,rp"]="r BOOLS BOOLO"
    ["19,ld"]="s 10" ["19,lp"]="s 23" ["19,ex"]="s 22" ["19,str"]="s 11"
    ["19,STMT"]="26" ["19,IF"]="3" ["19,FORIN"]="4" ["19,INCLUDE"]="5"
    ["19,BUILTIN"]="6" ["19,QUOTE"]="7" ["19,VAR"]="8" ["19,STR"]="9"
    ["19,BOOLS"]="48" ["19,BOOLO"]="18" ["19,UOP"]="19" ["19,BOOLA"]="21"
    ["19,BOOL"]="24" ["19,ARGS"]="25" ["20,cl"]="r ID id" ["20,rd"]="r ID id"
    ["20,or"]="r ID id" ["20,and"]="r ID id" ["20,in"]="r ID id"
    ["20,err"]="r ID id" ["20,pfx"]="r ID id" ["20,ppfx"]="r ID id"
    ["20,sfx"]="r ID id" ["20,ssfx"]="r ID id" ["20,upp"]="r ID id"
    ["20,uupp"]="r ID id" ["20,low"]="r ID id" ["20,llow"]="r ID id"
    ["21,cl"]="r BOOLO BOOLA" ["21,rd"]="r BOOLO BOOLA" ["21,or"]="r BOOLO BOOLA"
    ["21,and"]="s 49" ["21,rp"]="r BOOLO BOOLA" ["22,ld"]="r UOP ex"
    ["22,lp"]="r UOP ex" ["22,ex"]="r UOP ex" ["22,str"]="r UOP ex" ["23,ld"]="s 10"
    ["23,lp"]="s 23" ["23,ex"]="s 22" ["23,str"]="s 11" ["23,STMT"]="26"
    ["23,IF"]="3" ["23,FORIN"]="4" ["23,INCLUDE"]="5" ["23,BUILTIN"]="6"
    ["23,QUOTE"]="7" ["23,VAR"]="8" ["23,STR"]="9" ["23,BOOLS"]="50"
    ["23,BOOLO"]="18" ["23,UOP"]="19" ["23,BOOLA"]="21" ["23,BOOL"]="24"
    ["23,ARGS"]="25" ["24,cl"]="r BOOLA BOOL" ["24,rd"]="r BOOLA BOOL"
    ["24,or"]="r BOOLA BOOL" ["24,and"]="r BOOLA BOOL" ["24,rp"]="r BOOLA BOOL"
    ["25,ld"]="s 10" ["25,cl"]="r BOOL ARGS" ["25,rd"]="r BOOL ARGS"
    ["25,or"]="r BOOL ARGS" ["25,and"]="r BOOL ARGS" ["25,rp"]="r BOOL ARGS"
    ["25,ne"]="s 53" ["25,eq"]="s 54" ["25,gt"]="s 55" ["25,lt"]="s 56"
    ["25,ge"]="s 57" ["25,le"]="s 58" ["25,strne"]="s 59" ["25,streq"]="s 60"
    ["25,strgt"]="s 61" ["25,strlt"]="s 62" ["25,strcm"]="s 63" ["25,str"]="s 11"
    ["25,STMT"]="52" ["25,IF"]="3" ["25,FORIN"]="4" ["25,INCLUDE"]="5"
    ["25,BUILTIN"]="6" ["25,QUOTE"]="7" ["25,VAR"]="8" ["25,STR"]="9"
    ["25,BOP"]="51" ["26,ld"]="r ARGS STMT" ["26,cl"]="r ARGS STMT"
    ["26,rd"]="r ARGS STMT" ["26,or"]="r ARGS STMT" ["26,and"]="r ARGS STMT"
    ["26,rp"]="r ARGS STMT" ["26,ne"]="r ARGS STMT" ["26,eq"]="r ARGS STMT"
    ["26,gt"]="r ARGS STMT" ["26,lt"]="r ARGS STMT" ["26,ge"]="r ARGS STMT"
    ["26,le"]="r ARGS STMT" ["26,strne"]="r ARGS STMT" ["26,streq"]="r ARGS STMT"
    ["26,strgt"]="r ARGS STMT" ["26,strlt"]="r ARGS STMT" ["26,strcm"]="r ARGS STMT"
    ["26,str"]="r ARGS STMT" ["27,cl"]="s 64" ["28,ld"]="r DOC" ["28,cl"]="r DOC"
    ["28,rd"]="r DOC" ["28,str"]="r DOC" ["28,DOC"]="65"
    ["29,ld"]="r IF ld BOOLS rd" ["29,cl"]="r IF ld BOOLS rd"
    ["29,rd"]="r IF ld BOOLS rd" ["29,elif"]="r IF ld BOOLS rd"
    ["29,else"]="r IF ld BOOLS rd" ["29,or"]="r IF ld BOOLS rd"
    ["29,and"]="r IF ld BOOLS rd" ["29,rp"]="r IF ld BOOLS rd"
    ["29,ne"]="r IF ld BOOLS rd" ["29,eq"]="r IF ld BOOLS rd"
    ["29,gt"]="r IF ld BOOLS rd" ["29,lt"]="r IF ld BOOLS rd"
    ["29,ge"]="r IF ld BOOLS rd" ["29,le"]="r IF ld BOOLS rd"
    ["29,strne"]="r IF ld BOOLS rd" ["29,streq"]="r IF ld BOOLS rd"
    ["29,strgt"]="r IF ld BOOLS rd" ["29,strlt"]="r IF ld BOOLS rd"
    ["29,strcm"]="r IF ld BOOLS rd" ["29,str"]="r IF ld BOOLS rd"
    ["29,$"]="r IF ld BOOLS rd" ["30,in"]="s 66" ["31,str"]="s 11" ["31,STR"]="67"
    ["32,ld"]="s 10" ["32,str"]="s 11" ["32,STMT"]="26" ["32,IF"]="3"
    ["32,FORIN"]="4" ["32,INCLUDE"]="5" ["32,BUILTIN"]="6" ["32,QUOTE"]="7"
    ["32,VAR"]="8" ["32,STR"]="9" ["32,ARGS"]="68" ["33,ld"]="r VAR ld ID rd"
    ["33,cl"]="r VAR ld ID rd" ["33,rd"]="r VAR ld ID rd"
    ["33,elif"]="r VAR ld ID rd" ["33,else"]="r VAR ld ID rd"
    ["33,or"]="r VAR ld ID rd" ["33,and"]="r VAR ld ID rd"
    ["33,rp"]="r VAR ld ID rd" ["33,ne"]="r VAR ld ID rd" ["33,eq"]="r VAR ld ID rd"
    ["33,gt"]="r VAR ld ID rd" ["33,lt"]="r VAR ld ID rd" ["33,ge"]="r VAR ld ID rd"
    ["33,le"]="r VAR ld ID rd" ["33,strne"]="r VAR ld ID rd"
    ["33,streq"]="r VAR ld ID rd" ["33,strgt"]="r VAR ld ID rd"
    ["33,strlt"]="r VAR ld ID rd" ["33,strcm"]="r VAR ld ID rd"
    ["33,str"]="r VAR ld ID rd" ["33,$"]="r VAR ld ID rd" ["34,ld"]="s 72"
    ["34,rd"]="s 69" ["34,str"]="s 11" ["34,VAR"]="70" ["34,STR"]="71"
    ["35,ld"]="r MOD and" ["35,rd"]="r MOD and" ["35,str"]="r MOD and"
    ["36,ld"]="r MOD or" ["36,rd"]="r MOD or" ["36,str"]="r MOD or"
    ["37,ld"]="r MOD err" ["37,rd"]="r MOD err" ["37,str"]="r MOD err"
    ["38,ld"]="r MOD pfx" ["38,rd"]="r MOD pfx" ["38,str"]="r MOD pfx"
    ["39,ld"]="r MOD ppfx" ["39,rd"]="r MOD ppfx" ["39,str"]="r MOD ppfx"
    ["40,ld"]="r MOD sfx" ["40,rd"]="r MOD sfx" ["40,str"]="r MOD sfx"
    ["41,ld"]="r MOD ssfx" ["41,rd"]="r MOD ssfx" ["41,str"]="r MOD ssfx"
    ["42,ld"]="r MOD upp" ["42,rd"]="r MOD upp" ["42,str"]="r MOD upp"
    ["43,ld"]="r MOD uupp" ["43,rd"]="r MOD uupp" ["43,str"]="r MOD uupp"
    ["44,ld"]="r MOD low" ["44,rd"]="r MOD low" ["44,str"]="r MOD low"
    ["45,ld"]="r MOD llow" ["45,rd"]="r MOD llow" ["45,str"]="r MOD llow"
    ["46,ld"]="s 10" ["46,str"]="s 11" ["46,STMT"]="26" ["46,IF"]="3"
    ["46,FORIN"]="4" ["46,INCLUDE"]="5" ["46,BUILTIN"]="6" ["46,QUOTE"]="7"
    ["46,VAR"]="8" ["46,STR"]="9" ["46,ARGS"]="73" ["47,ld"]="s 10" ["47,lp"]="s 23"
    ["47,ex"]="s 22" ["47,str"]="s 11" ["47,STMT"]="26" ["47,IF"]="3"
    ["47,FORIN"]="4" ["47,INCLUDE"]="5" ["47,BUILTIN"]="6" ["47,QUOTE"]="7"
    ["47,VAR"]="8" ["47,STR"]="9" ["47,UOP"]="75" ["47,BOOLA"]="74" ["47,BOOL"]="24"
    ["47,ARGS"]="25" ["48,cl"]="r BOOLS UOP BOOLS" ["48,rd"]="r BOOLS UOP BOOLS"
    ["48,rp"]="r BOOLS UOP BOOLS" ["49,ld"]="s 10" ["49,lp"]="s 78" ["49,ex"]="s 22"
    ["49,str"]="s 11" ["49,STMT"]="26" ["49,IF"]="3" ["49,FORIN"]="4"
    ["49,INCLUDE"]="5" ["49,BUILTIN"]="6" ["49,QUOTE"]="7" ["49,VAR"]="8"
    ["49,STR"]="9" ["49,UOP"]="77" ["49,BOOL"]="76" ["49,ARGS"]="25"
    ["50,rp"]="s 79" ["51,ld"]="s 10" ["51,str"]="s 11" ["51,STMT"]="26"
    ["51,IF"]="3" ["51,FORIN"]="4" ["51,INCLUDE"]="5" ["51,BUILTIN"]="6"
    ["51,QUOTE"]="7" ["51,VAR"]="8" ["51,STR"]="9" ["51,ARGS"]="80"
    ["52,ld"]="r ARGS ARGS STMT" ["52,cl"]="r ARGS ARGS STMT"
    ["52,rd"]="r ARGS ARGS STMT" ["52,or"]="r ARGS ARGS STMT"
    ["52,and"]="r ARGS ARGS STMT" ["52,rp"]="r ARGS ARGS STMT"
    ["52,ne"]="r ARGS ARGS STMT" ["52,eq"]="r ARGS ARGS STMT"
    ["52,gt"]="r ARGS ARGS STMT" ["52,lt"]="r ARGS ARGS STMT"
    ["52,ge"]="r ARGS ARGS STMT" ["52,le"]="r ARGS ARGS STMT"
    ["52,strne"]="r ARGS ARGS STMT" ["52,streq"]="r ARGS ARGS STMT"
    ["52,strgt"]="r ARGS ARGS STMT" ["52,strlt"]="r ARGS ARGS STMT"
    ["52,strcm"]="r ARGS ARGS STMT" ["52,str"]="r ARGS ARGS STMT"
    ["53,ld"]="r BOP ne" ["53,str"]="r BOP ne" ["54,ld"]="r BOP eq"
    ["54,str"]="r BOP eq" ["55,ld"]="r BOP gt" ["55,str"]="r BOP gt"
    ["56,ld"]="r BOP lt" ["56,str"]="r BOP lt" ["57,ld"]="r BOP ge"
    ["57,str"]="r BOP ge" ["58,ld"]="r BOP le" ["58,str"]="r BOP le"
    ["59,ld"]="r BOP strne" ["59,str"]="r BOP strne" ["60,ld"]="r BOP streq"
    ["60,str"]="r BOP streq" ["61,ld"]="r BOP strgt" ["61,str"]="r BOP strgt"
    ["62,ld"]="r BOP strlt" ["62,str"]="r BOP strlt" ["63,ld"]="r BOP strcm"
    ["63,str"]="r BOP strcm" ["64,ld"]="r DOC" ["64,rd"]="r DOC" ["64,elif"]="r DOC"
    ["64,else"]="r DOC" ["64,str"]="r DOC" ["64,DOC"]="81" ["65,ld"]="s 10"
    ["65,cl"]="s 82" ["65,rd"]="s 83" ["65,str"]="s 11" ["65,STMT"]="2"
    ["65,IF"]="3" ["65,FORIN"]="4" ["65,INCLUDE"]="5" ["65,BUILTIN"]="6"
    ["65,QUOTE"]="7" ["65,VAR"]="8" ["65,STR"]="9" ["66,ld"]="s 10"
    ["66,str"]="s 11" ["66,STMT"]="26" ["66,IF"]="3" ["66,FORIN"]="4"
    ["66,INCLUDE"]="5" ["66,BUILTIN"]="6" ["66,QUOTE"]="7" ["66,VAR"]="8"
    ["66,STR"]="9" ["66,ARGS"]="84" ["67,rd"]="s 85" ["68,ld"]="s 10"
    ["68,rd"]="s 86" ["68,str"]="s 11" ["68,STMT"]="52" ["68,IF"]="3"
    ["68,FORIN"]="4" ["68,INCLUDE"]="5" ["68,BUILTIN"]="6" ["68,QUOTE"]="7"
    ["68,VAR"]="8" ["68,STR"]="9" ["69,ld"]="r VAR ld ID MOD rd"
    ["69,cl"]="r VAR ld ID MOD rd" ["69,rd"]="r VAR ld ID MOD rd"
    ["69,elif"]="r VAR ld ID MOD rd" ["69,else"]="r VAR ld ID MOD rd"
    ["69,or"]="r VAR ld ID MOD rd" ["69,and"]="r VAR ld ID MOD rd"
    ["69,rp"]="r VAR ld ID MOD rd" ["69,ne"]="r VAR ld ID MOD rd"
    ["69,eq"]="r VAR ld ID MOD rd" ["69,gt"]="r VAR ld ID MOD rd"
    ["69,lt"]="r VAR ld ID MOD rd" ["69,ge"]="r VAR ld ID MOD rd"
    ["69,le"]="r VAR ld ID MOD rd" ["69,strne"]="r VAR ld ID MOD rd"
    ["69,streq"]="r VAR ld ID MOD rd" ["69,strgt"]="r VAR ld ID MOD rd"
    ["69,strlt"]="r VAR ld ID MOD rd" ["69,strcm"]="r VAR ld ID MOD rd"
    ["69,str"]="r VAR ld ID MOD rd" ["69,$"]="r VAR ld ID MOD rd" ["70,rd"]="s 87"
    ["71,rd"]="s 88" ["72,id"]="s 20" ["72,ID"]="89" ["73,ld"]="s 10"
    ["73,rd"]="s 90" ["73,str"]="s 11" ["73,STMT"]="52" ["73,IF"]="3"
    ["73,FORIN"]="4" ["73,INCLUDE"]="5" ["73,BUILTIN"]="6" ["73,QUOTE"]="7"
    ["73,VAR"]="8" ["73,STR"]="9" ["74,cl"]="r BOOLO BOOLO or BOOLA"
    ["74,rd"]="r BOOLO BOOLO or BOOLA" ["74,or"]="r BOOLO BOOLO or BOOLA"
    ["74,and"]="s 49" ["74,rp"]="r BOOLO BOOLO or BOOLA" ["75,ld"]="s 10"
    ["75,lp"]="s 23" ["75,str"]="s 11" ["75,STMT"]="26" ["75,IF"]="3"
    ["75,FORIN"]="4" ["75,INCLUDE"]="5" ["75,BUILTIN"]="6" ["75,QUOTE"]="7"
    ["75,VAR"]="8" ["75,STR"]="9" ["75,BOOLA"]="91" ["75,BOOL"]="24"
    ["75,ARGS"]="25" ["76,cl"]="r BOOLA BOOLA and BOOL"
    ["76,rd"]="r BOOLA BOOLA and BOOL" ["76,or"]="r BOOLA BOOLA and BOOL"
    ["76,and"]="r BOOLA BOOLA and BOOL" ["76,rp"]="r BOOLA BOOLA and BOOL"
    ["77,ld"]="s 10" ["77,lp"]="s 93" ["77,str"]="s 11" ["77,STMT"]="26"
    ["77,IF"]="3" ["77,FORIN"]="4" ["77,INCLUDE"]="5" ["77,BUILTIN"]="6"
    ["77,QUOTE"]="7" ["77,VAR"]="8" ["77,STR"]="9" ["77,BOOL"]="92" ["77,ARGS"]="25"
    ["78,ld"]="s 10" ["78,lp"]="s 23" ["78,ex"]="s 22" ["78,str"]="s 11"
    ["78,STMT"]="26" ["78,IF"]="3" ["78,FORIN"]="4" ["78,INCLUDE"]="5"
    ["78,BUILTIN"]="6" ["78,QUOTE"]="7" ["78,VAR"]="8" ["78,STR"]="9"
    ["78,BOOLS"]="94" ["78,BOOLO"]="18" ["78,UOP"]="19" ["78,BOOLA"]="21"
    ["78,BOOL"]="24" ["78,ARGS"]="25" ["79,cl"]="r BOOLA lp BOOLS rp"
    ["79,rd"]="r BOOLA lp BOOLS rp" ["79,or"]="r BOOLA lp BOOLS rp"
    ["79,and"]="r BOOLA lp BOOLS rp" ["79,rp"]="r BOOLA lp BOOLS rp"
    ["80,ld"]="s 10" ["80,cl"]="r BOOL ARGS BOP ARGS"
    ["80,rd"]="r BOOL ARGS BOP ARGS" ["80,or"]="r BOOL ARGS BOP ARGS"
    ["80,and"]="r BOOL ARGS BOP ARGS" ["80,rp"]="r BOOL ARGS BOP ARGS"
    ["80,str"]="s 11" ["80,STMT"]="52" ["80,IF"]="3" ["80,FORIN"]="4"
    ["80,INCLUDE"]="5" ["80,BUILTIN"]="6" ["80,QUOTE"]="7" ["80,VAR"]="8"
    ["80,STR"]="9" ["81,ld"]="s 10" ["81,rd"]="r ELIF" ["81,elif"]="r ELIF"
    ["81,else"]="r ELIF" ["81,str"]="s 11" ["81,STMT"]="2" ["81,IF"]="3"
    ["81,FORIN"]="4" ["81,INCLUDE"]="5" ["81,BUILTIN"]="6" ["81,QUOTE"]="7"
    ["81,VAR"]="8" ["81,STR"]="9" ["81,ELIF"]="95" ["82,ld"]="r DOC"
    ["82,rd"]="r DOC" ["82,str"]="r DOC" ["82,DOC"]="96"
    ["83,ld"]="r IF ld BOOLS cl DOC rd" ["83,cl"]="r IF ld BOOLS cl DOC rd"
    ["83,rd"]="r IF ld BOOLS cl DOC rd" ["83,elif"]="r IF ld BOOLS cl DOC rd"
    ["83,else"]="r IF ld BOOLS cl DOC rd" ["83,or"]="r IF ld BOOLS cl DOC rd"
    ["83,and"]="r IF ld BOOLS cl DOC rd" ["83,rp"]="r IF ld BOOLS cl DOC rd"
    ["83,ne"]="r IF ld BOOLS cl DOC rd" ["83,eq"]="r IF ld BOOLS cl DOC rd"
    ["83,gt"]="r IF ld BOOLS cl DOC rd" ["83,lt"]="r IF ld BOOLS cl DOC rd"
    ["83,ge"]="r IF ld BOOLS cl DOC rd" ["83,le"]="r IF ld BOOLS cl DOC rd"
    ["83,strne"]="r IF ld BOOLS cl DOC rd" ["83,streq"]="r IF ld BOOLS cl DOC rd"
    ["83,strgt"]="r IF ld BOOLS cl DOC rd" ["83,strlt"]="r IF ld BOOLS cl DOC rd"
    ["83,strcm"]="r IF ld BOOLS cl DOC rd" ["83,str"]="r IF ld BOOLS cl DOC rd"
    ["83,$"]="r IF ld BOOLS cl DOC rd" ["84,ld"]="s 10" ["84,cl"]="s 97"
    ["84,str"]="s 11" ["84,STMT"]="52" ["84,IF"]="3" ["84,FORIN"]="4"
    ["84,INCLUDE"]="5" ["84,BUILTIN"]="6" ["84,QUOTE"]="7" ["84,VAR"]="8"
    ["84,STR"]="9" ["85,ld"]="r INCLUDE ld include cl STR rd"
    ["85,cl"]="r INCLUDE ld include cl STR rd"
    ["85,rd"]="r INCLUDE ld include cl STR rd"
    ["85,elif"]="r INCLUDE ld include cl STR rd"
    ["85,else"]="r INCLUDE ld include cl STR rd"
    ["85,or"]="r INCLUDE ld include cl STR rd"
    ["85,and"]="r INCLUDE ld include cl STR rd"
    ["85,rp"]="r INCLUDE ld include cl STR rd"
    ["85,ne"]="r INCLUDE ld include cl STR rd"
    ["85,eq"]="r INCLUDE ld include cl STR rd"
    ["85,gt"]="r INCLUDE ld include cl STR rd"
    ["85,lt"]="r INCLUDE ld include cl STR rd"
    ["85,ge"]="r INCLUDE ld include cl STR rd"
    ["85,le"]="r INCLUDE ld include cl STR rd"
    ["85,strne"]="r INCLUDE ld include cl STR rd"
    ["85,streq"]="r INCLUDE ld include cl STR rd"
    ["85,strgt"]="r INCLUDE ld include cl STR rd"
    ["85,strlt"]="r INCLUDE ld include cl STR rd"
    ["85,strcm"]="r INCLUDE ld include cl STR rd"
    ["85,str"]="r INCLUDE ld include cl STR rd"
    ["85,$"]="r INCLUDE ld include cl STR rd" ["86,ld"]="r BUILTIN ld ID cl ARGS rd"
    ["86,cl"]="r BUILTIN ld ID cl ARGS rd" ["86,rd"]="r BUILTIN ld ID cl ARGS rd"
    ["86,elif"]="r BUILTIN ld ID cl ARGS rd"
    ["86,else"]="r BUILTIN ld ID cl ARGS rd" ["86,or"]="r BUILTIN ld ID cl ARGS rd"
    ["86,and"]="r BUILTIN ld ID cl ARGS rd" ["86,rp"]="r BUILTIN ld ID cl ARGS rd"
    ["86,ne"]="r BUILTIN ld ID cl ARGS rd" ["86,eq"]="r BUILTIN ld ID cl ARGS rd"
    ["86,gt"]="r BUILTIN ld ID cl ARGS rd" ["86,lt"]="r BUILTIN ld ID cl ARGS rd"
    ["86,ge"]="r BUILTIN ld ID cl ARGS rd" ["86,le"]="r BUILTIN ld ID cl ARGS rd"
    ["86,strne"]="r BUILTIN ld ID cl ARGS rd"
    ["86,streq"]="r BUILTIN ld ID cl ARGS rd"
    ["86,strgt"]="r BUILTIN ld ID cl ARGS rd"
    ["86,strlt"]="r BUILTIN ld ID cl ARGS rd"
    ["86,strcm"]="r BUILTIN ld ID cl ARGS rd"
    ["86,str"]="r BUILTIN ld ID cl ARGS rd" ["86,$"]="r BUILTIN ld ID cl ARGS rd"
    ["87,ld"]="r VAR ld ID MOD VAR rd" ["87,cl"]="r VAR ld ID MOD VAR rd"
    ["87,rd"]="r VAR ld ID MOD VAR rd" ["87,elif"]="r VAR ld ID MOD VAR rd"
    ["87,else"]="r VAR ld ID MOD VAR rd" ["87,or"]="r VAR ld ID MOD VAR rd"
    ["87,and"]="r VAR ld ID MOD VAR rd" ["87,rp"]="r VAR ld ID MOD VAR rd"
    ["87,ne"]="r VAR ld ID MOD VAR rd" ["87,eq"]="r VAR ld ID MOD VAR rd"
    ["87,gt"]="r VAR ld ID MOD VAR rd" ["87,lt"]="r VAR ld ID MOD VAR rd"
    ["87,ge"]="r VAR ld ID MOD VAR rd" ["87,le"]="r VAR ld ID MOD VAR rd"
    ["87,strne"]="r VAR ld ID MOD VAR rd" ["87,streq"]="r VAR ld ID MOD VAR rd"
    ["87,strgt"]="r VAR ld ID MOD VAR rd" ["87,strlt"]="r VAR ld ID MOD VAR rd"
    ["87,strcm"]="r VAR ld ID MOD VAR rd" ["87,str"]="r VAR ld ID MOD VAR rd"
    ["87,$"]="r VAR ld ID MOD VAR rd" ["88,ld"]="r VAR ld ID MOD STR rd"
    ["88,cl"]="r VAR ld ID MOD STR rd" ["88,rd"]="r VAR ld ID MOD STR rd"
    ["88,elif"]="r VAR ld ID MOD STR rd" ["88,else"]="r VAR ld ID MOD STR rd"
    ["88,or"]="r VAR ld ID MOD STR rd" ["88,and"]="r VAR ld ID MOD STR rd"
    ["88,rp"]="r VAR ld ID MOD STR rd" ["88,ne"]="r VAR ld ID MOD STR rd"
    ["88,eq"]="r VAR ld ID MOD STR rd" ["88,gt"]="r VAR ld ID MOD STR rd"
    ["88,lt"]="r VAR ld ID MOD STR rd" ["88,ge"]="r VAR ld ID MOD STR rd"
    ["88,le"]="r VAR ld ID MOD STR rd" ["88,strne"]="r VAR ld ID MOD STR rd"
    ["88,streq"]="r VAR ld ID MOD STR rd" ["88,strgt"]="r VAR ld ID MOD STR rd"
    ["88,strlt"]="r VAR ld ID MOD STR rd" ["88,strcm"]="r VAR ld ID MOD STR rd"
    ["88,str"]="r VAR ld ID MOD STR rd" ["88,$"]="r VAR ld ID MOD STR rd"
    ["89,rd"]="s 33" ["89,or"]="s 36" ["89,and"]="s 35" ["89,err"]="s 37"
    ["89,pfx"]="s 38" ["89,ppfx"]="s 39" ["89,sfx"]="s 40" ["89,ssfx"]="s 41"
    ["89,upp"]="s 42" ["89,uupp"]="s 43" ["89,low"]="s 44" ["89,llow"]="s 45"
    ["89,MOD"]="34" ["90,ld"]="r QUOTE ld quote cl ARGS rd"
    ["90,cl"]="r QUOTE ld quote cl ARGS rd" ["90,rd"]="r QUOTE ld quote cl ARGS rd"
    ["90,elif"]="r QUOTE ld quote cl ARGS rd"
    ["90,else"]="r QUOTE ld quote cl ARGS rd"
    ["90,or"]="r QUOTE ld quote cl ARGS rd" ["90,and"]="r QUOTE ld quote cl ARGS rd"
    ["90,rp"]="r QUOTE ld quote cl ARGS rd" ["90,ne"]="r QUOTE ld quote cl ARGS rd"
    ["90,eq"]="r QUOTE ld quote cl ARGS rd" ["90,gt"]="r QUOTE ld quote cl ARGS rd"
    ["90,lt"]="r QUOTE ld quote cl ARGS rd" ["90,ge"]="r QUOTE ld quote cl ARGS rd"
    ["90,le"]="r QUOTE ld quote cl ARGS rd"
    ["90,strne"]="r QUOTE ld quote cl ARGS rd"
    ["90,streq"]="r QUOTE ld quote cl ARGS rd"
    ["90,strgt"]="r QUOTE ld quote cl ARGS rd"
    ["90,strlt"]="r QUOTE ld quote cl ARGS rd"
    ["90,strcm"]="r QUOTE ld quote cl ARGS rd"
    ["90,str"]="r QUOTE ld quote cl ARGS rd" ["90,$"]="r QUOTE ld quote cl ARGS rd"
    ["91,cl"]="r BOOLO BOOLO or UOP BOOLA" ["91,rd"]="r BOOLO BOOLO or UOP BOOLA"
    ["91,or"]="r BOOLO BOOLO or UOP BOOLA" ["91,and"]="s 49"
    ["91,rp"]="r BOOLO BOOLO or UOP BOOLA" ["92,cl"]="r BOOLA BOOLA and UOP BOOL"
    ["92,rd"]="r BOOLA BOOLA and UOP BOOL" ["92,or"]="r BOOLA BOOLA and UOP BOOL"
    ["92,and"]="r BOOLA BOOLA and UOP BOOL" ["92,rp"]="r BOOLA BOOLA and UOP BOOL"
    ["93,ld"]="s 10" ["93,lp"]="s 23" ["93,ex"]="s 22" ["93,str"]="s 11"
    ["93,STMT"]="26" ["93,IF"]="3" ["93,FORIN"]="4" ["93,INCLUDE"]="5"
    ["93,BUILTIN"]="6" ["93,QUOTE"]="7" ["93,VAR"]="8" ["93,STR"]="9"
    ["93,BOOLS"]="98" ["93,BOOLO"]="18" ["93,UOP"]="19" ["93,BOOLA"]="21"
    ["93,BOOL"]="24" ["93,ARGS"]="25" ["94,rp"]="s 99" ["95,rd"]="r ELSE"
    ["95,elif"]="s 101" ["95,else"]="s 102" ["95,ELSE"]="100" ["96,ld"]="s 10"
    ["96,rd"]="s 103" ["96,str"]="s 11" ["96,STMT"]="2" ["96,IF"]="3"
    ["96,FORIN"]="4" ["96,INCLUDE"]="5" ["96,BUILTIN"]="6" ["96,QUOTE"]="7"
    ["96,VAR"]="8" ["96,STR"]="9" ["97,ld"]="r DOC" ["97,rd"]="r DOC"
    ["97,str"]="r DOC" ["97,DOC"]="104" ["98,rp"]="s 105"
    ["99,cl"]="r BOOLA BOOLA and lp BOOLS rp"
    ["99,rd"]="r BOOLA BOOLA and lp BOOLS rp"
    ["99,or"]="r BOOLA BOOLA and lp BOOLS rp"
    ["99,and"]="r BOOLA BOOLA and lp BOOLS rp"
    ["99,rp"]="r BOOLA BOOLA and lp BOOLS rp" ["100,rd"]="s 106" ["101,ld"]="s 10"
    ["101,lp"]="s 23" ["101,ex"]="s 22" ["101,str"]="s 11" ["101,STMT"]="26"
    ["101,IF"]="3" ["101,FORIN"]="4" ["101,INCLUDE"]="5" ["101,BUILTIN"]="6"
    ["101,QUOTE"]="7" ["101,VAR"]="8" ["101,STR"]="9" ["101,BOOLS"]="107"
    ["101,BOOLO"]="18" ["101,UOP"]="19" ["101,BOOLA"]="21" ["101,BOOL"]="24"
    ["101,ARGS"]="25" ["102,cl"]="s 108" ["103,ld"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,cl"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,rd"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,elif"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,else"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,or"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,and"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,rp"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,ne"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,eq"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,gt"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,lt"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,ge"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,le"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,strne"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,streq"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,strgt"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,strlt"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,strcm"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,str"]="r IF ld BOOLS cl DOC cl DOC rd"
    ["103,$"]="r IF ld BOOLS cl DOC cl DOC rd" ["104,ld"]="s 10" ["104,rd"]="s 109"
    ["104,str"]="s 11" ["104,STMT"]="2" ["104,IF"]="3" ["104,FORIN"]="4"
    ["104,INCLUDE"]="5" ["104,BUILTIN"]="6" ["104,QUOTE"]="7" ["104,VAR"]="8"
    ["104,STR"]="9" ["105,cl"]="r BOOLA BOOLA and UOP lp BOOLS rp"
    ["105,rd"]="r BOOLA BOOLA and UOP lp BOOLS rp"
    ["105,or"]="r BOOLA BOOLA and UOP lp BOOLS rp"
    ["105,and"]="r BOOLA BOOLA and UOP lp BOOLS rp"
    ["105,rp"]="r BOOLA BOOLA and UOP lp BOOLS rp"
    ["106,ld"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,cl"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,rd"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,elif"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,else"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,or"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,and"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,rp"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,ne"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,eq"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,gt"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,lt"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,ge"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,le"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,strne"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,streq"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,strgt"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,strlt"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,strcm"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,str"]="r IF ld if BOOLS cl DOC ELIF ELSE rd"
    ["106,$"]="r IF ld if BOOLS cl DOC ELIF ELSE rd" ["107,cl"]="s 110"
    ["108,ld"]="r DOC" ["108,rd"]="r DOC" ["108,str"]="r DOC" ["108,DOC"]="111"
    ["109,ld"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,cl"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,rd"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,elif"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,else"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,or"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,and"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,rp"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,ne"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,eq"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,gt"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,lt"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,ge"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,le"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,strne"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,streq"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,strgt"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,strlt"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,strcm"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,str"]="r FORIN ld for ID in ARGS cl DOC rd"
    ["109,$"]="r FORIN ld for ID in ARGS cl DOC rd" ["110,ld"]="r DOC"
    ["110,rd"]="r DOC" ["110,elif"]="r DOC" ["110,else"]="r DOC" ["110,str"]="r DOC"
    ["110,DOC"]="112" ["111,ld"]="s 10" ["111,rd"]="r ELSE else cl DOC"
    ["111,str"]="s 11" ["111,STMT"]="2" ["111,IF"]="3" ["111,FORIN"]="4"
    ["111,INCLUDE"]="5" ["111,BUILTIN"]="6" ["111,QUOTE"]="7" ["111,VAR"]="8"
    ["111,STR"]="9" ["112,ld"]="s 10" ["112,rd"]="r ELIF ELIF elif BOOLS cl DOC"
    ["112,elif"]="r ELIF ELIF elif BOOLS cl DOC"
    ["112,else"]="r ELIF ELIF elif BOOLS cl DOC" ["112,str"]="s 11" ["112,STMT"]="2"
    ["112,IF"]="3" ["112,FORIN"]="4" ["112,INCLUDE"]="5" ["112,BUILTIN"]="6"
    ["112,QUOTE"]="7" ["112,VAR"]="8" ["112,STR"]="9"
) # }}}
# <<< BPT_PARSE_TABLE_E <<<

return 0 2>/dev/null || bpt.main "$@"
