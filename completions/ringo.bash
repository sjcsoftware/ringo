#!/bin/bash

__ringo_cursor_index_in_current_word() {
    local remaining="${COMP_LINE}"

    local word
    for word in "${COMP_WORDS[@]::COMP_CWORD}"; do
        remaining="${remaining##*([[:space:]])"${word}"*([[:space:]])}"
    done

    local -ir index="$((COMP_POINT - ${#COMP_LINE} + ${#remaining}))"
    if [[ "${index}" -le 0 ]]; then
        printf 0
    else
        printf %s "${index}"
    fi
}

# positional arguments:
#
# - 1: the current (sub)command's count of positional arguments
#
# required variables:
#
# - repeating_flags: the repeating flags that the current (sub)command can accept
# - non_repeating_flags: the non-repeating flags that the current (sub)command can accept
# - repeating_options: the repeating options that the current (sub)command can accept
# - non_repeating_options: the non-repeating options that the current (sub)command can accept
# - positional_number: value ignored
# - unparsed_words: unparsed words from the current command line
#
# modified variables:
#
# - non_repeating_flags: remove flags for this (sub)command that are already on the command line
# - non_repeating_options: remove options for this (sub)command that are already on the command line
# - positional_number: set to the current positional number
# - unparsed_words: remove all flags, options, and option values for this (sub)command
__ringo_offer_flags_options() {
    local -ir positional_count="${1}"
    positional_number=0

    local was_flag_option_terminator_seen=false
    local is_parsing_option_value=false

    local -ar unparsed_word_indices=("${!unparsed_words[@]}")
    local -i word_index
    for word_index in "${unparsed_word_indices[@]}"; do
        if "${is_parsing_option_value}"; then
            # This word is an option value:
            # Reset marker for next word iff not currently the last word
            [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]] && is_parsing_option_value=false
            unset "unparsed_words[${word_index}]"
            # Do not process this word as a flag or an option
            continue
        fi

        local word="${unparsed_words["${word_index}"]}"
        if ! "${was_flag_option_terminator_seen}"; then
            case "${word}" in
            --)
                unset "unparsed_words[${word_index}]"
                # by itself -- is a flag/option terminator, but if it is the last word, it is the start of a completion
                if [[ "${word_index}" -ne "${unparsed_word_indices[${#unparsed_word_indices[@]} - 1]}" ]]; then
                    was_flag_option_terminator_seen=true
                fi
                continue
                ;;
            -*)
                # ${word} is a flag or an option
                # If ${word} is an option, mark that the next word to be parsed is an option value
                local option
                for option in "${repeating_options[@]}" "${non_repeating_options[@]}"; do
                    [[ "${word}" = "${option}" ]] && is_parsing_option_value=true && break
                done

                # Remove ${word} from ${non_repeating_flags} or ${non_repeating_options} so it isn't offered again
                local not_found=true
                local -i index
                for index in "${!non_repeating_flags[@]}"; do
                    if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                        unset "non_repeating_flags[${index}]"
                        non_repeating_flags=("${non_repeating_flags[@]}")
                        not_found=false
                        break
                    fi
                done
                if "${not_found}"; then
                    for index in "${!non_repeating_flags[@]}"; do
                        if [[ "${non_repeating_flags[${index}]}" = "${word}" ]]; then
                            unset "non_repeating_flags[${index}]"
                            non_repeating_flags=("${non_repeating_flags[@]}")
                            break
                        fi
                    done
                fi
                unset "unparsed_words[${word_index}]"
                continue
                ;;
            esac
        fi

        # ${word} is neither a flag, nor an option, nor an option value
        if [[ "${positional_number}" -lt "${positional_count}" || "${positional_count}" -lt 0 ]]; then
            # ${word} is a positional
            ((positional_number++))
            unset "unparsed_words[${word_index}]"
        else
            if [[ -z "${word}" ]]; then
                # Could be completing a flag, option, or subcommand
                positional_number=-1
            else
                # ${word} is a subcommand or invalid, so stop processing this (sub)command
                positional_number=-2
            fi
            break
        fi
    done

    unparsed_words=("${unparsed_words[@]}")

    if\
        ! "${was_flag_option_terminator_seen}"\
        && ! "${is_parsing_option_value}"\
        && [[ ("${cur}" = -* && "${positional_number}" -ge 0) || "${positional_number}" -eq -1 ]]
    then
        COMPREPLY+=($(compgen -W "${repeating_flags[*]} ${non_repeating_flags[*]} ${repeating_options[*]} ${non_repeating_options[*]}" -- "${cur}"))
    fi
}

__ringo_add_completions() {
    local completion
    while IFS='' read -r completion; do
        COMPREPLY+=("${completion}")
    done < <(IFS=$'\n' compgen "${@}" -- "${cur}")
}

__ringo_custom_complete() {
    if [[ -n "${cur}" || -z ${COMP_WORDS[${COMP_CWORD}]} || "${COMP_LINE:${COMP_POINT}:1}" != ' ' ]]; then
        local -ar words=("${COMP_WORDS[@]}")
    else
        local -ar words=("${COMP_WORDS[@]::${COMP_CWORD}}" '' "${COMP_WORDS[@]:${COMP_CWORD}}")
    fi

    "${COMP_WORDS[0]}" "${@}" "${words[@]}"
}

_ringo() {
    local state
    state="$(shopt -p;shopt -po)"
    trap "${state//$'\n'/;}" RETURN
    shopt -s extglob
    set +o history +o posix

    local -xr SAP_SHELL=bash
    local -x SAP_SHELL_VERSION
    SAP_SHELL_VERSION="$(IFS='.';printf %s "${BASH_VERSINFO[*]}")"
    local -r SAP_SHELL_VERSION

    local -r cur="${2}"
    local -r prev="${3}"

    local -i positional_number
    local -a unparsed_words=("${COMP_WORDS[@]:1:${COMP_CWORD}}")

    local -a repeating_flags=()
    local -a non_repeating_flags=(--version -h --help)
    local -a repeating_options=()
    local -a non_repeating_options=()
    __ringo_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    convert|plan|formats|capabilities|inspect|tools|compress|metadata|edit|crop|annotate|redact|archive|extract|watch|batch|providers|settings|version|help)
        # Offer subcommand argument completions
        "_ringo_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'convert plan formats capabilities inspect tools compress metadata edit crop annotate redact archive extract watch batch providers settings version help' -- "${cur}"))
        ;;
    esac
}

_ringo_convert() {
    repeating_flags=()
    non_repeating_flags=(--keep-timestamps --strip-metadata --ocr --no-ocr --overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-t --to --quality --preset --dpi --pages --sheet --page-size --fps --max-width --max-duration --audio-bitrate --provider --timeout -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-t'|'--to')
        return
        ;;
    '--quality')
        return
        ;;
    '--preset')
        return
        ;;
    '--dpi')
        return
        ;;
    '--pages')
        return
        ;;
    '--sheet')
        return
        ;;
    '--page-size')
        return
        ;;
    '--fps')
        return
        ;;
    '--max-width')
        return
        ;;
    '--max-duration')
        return
        ;;
    '--audio-bitrate')
        return
        ;;
    '--provider')
        return
        ;;
    '--timeout')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_plan() {
    repeating_flags=()
    non_repeating_flags=(--keep-timestamps --strip-metadata --ocr --no-ocr --overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-t --to --quality --preset --dpi --pages --sheet --page-size --fps --max-width --max-duration --audio-bitrate --provider --timeout -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-t'|'--to')
        return
        ;;
    '--quality')
        return
        ;;
    '--preset')
        return
        ;;
    '--dpi')
        return
        ;;
    '--pages')
        return
        ;;
    '--sheet')
        return
        ;;
    '--page-size')
        return
        ;;
    '--fps')
        return
        ;;
    '--max-width')
        return
        ;;
    '--max-duration')
        return
        ;;
    '--audio-bitrate')
        return
        ;;
    '--provider')
        return
        ;;
    '--timeout')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_formats() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--category)
    __ringo_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--category')
        return
        ;;
    esac
}

_ringo_capabilities() {
    repeating_flags=()
    non_repeating_flags=(--all --available --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--from --to)
    __ringo_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--from')
        return
        ;;
    '--to')
        return
        ;;
    esac
}

_ringo_inspect() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 1

    # Offer positional completions
    case "${positional_number}" in
    1)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_tools() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 0
}

_ringo_compress() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--preset --target-size -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--preset')
        return
        ;;
    '--target-size')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_metadata() {
    repeating_flags=()
    non_repeating_flags=(--version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    show|strip|set)
        # Offer subcommand argument completions
        "_ringo_metadata_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'show strip set' -- "${cur}"))
        ;;
    esac
}

_ringo_metadata_show() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 1

    # Offer positional completions
    case "${positional_number}" in
    1)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_metadata_strip() {
    repeating_flags=()
    non_repeating_flags=(--location-only --overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_metadata_set() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=(--field)
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--field')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit() {
    repeating_flags=()
    non_repeating_flags=(--version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 0

    # Offer subcommand / subcommand argument completions
    local -r subcommand="${unparsed_words[0]}"
    unset 'unparsed_words[0]'
    unparsed_words=("${unparsed_words[@]}")
    case "${subcommand}" in
    rotate|flip|resize|trim|extract-audio|mute|pdf|merge)
        # Offer subcommand argument completions
        "_ringo_edit_${subcommand}"
        ;;
    *)
        # Offer subcommand completions
        COMPREPLY+=($(compgen -W 'rotate flip resize trim extract-audio mute pdf merge' -- "${cur}"))
        ;;
    esac
}

_ringo_edit_rotate() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--degrees -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--degrees')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_flip() {
    repeating_flags=()
    non_repeating_flags=(--vertical --overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_resize() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--percent --max --width --height -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--percent')
        return
        ;;
    '--max')
        return
        ;;
    '--width')
        return
        ;;
    '--height')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_trim() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--start --end -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--start')
        return
        ;;
    '--end')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_extract-audio() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_mute() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_pdf() {
    repeating_flags=()
    non_repeating_flags=(--reverse --split --overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--rotate --pages --delete --extract --order -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--rotate')
        return
        ;;
    '--pages')
        return
        ;;
    '--delete')
        return
        ;;
    '--extract')
        return
        ;;
    '--order')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_edit_merge() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_crop() {
    repeating_flags=()
    non_repeating_flags=(--normalized --overwrite --dry-run --in-place --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--rect --aspect --pages -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--rect')
        return
        ;;
    '--aspect')
        return
        ;;
    '--pages')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_annotate() {
    repeating_flags=()
    non_repeating_flags=(--flatten --overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--spec -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--spec')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_redact() {
    repeating_flags=()
    non_repeating_flags=(--case-sensitive --no-ocr --overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=(--text --pattern)
    non_repeating_options=(--regions --dpi -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--regions')
        return
        ;;
    '--text')
        return
        ;;
    '--pattern')
        return
        ;;
    '--dpi')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_archive() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--format -o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '--format')
        return
        ;;
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_extract() {
    repeating_flags=()
    non_repeating_flags=(--overwrite --dry-run --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-o --output --output-dir --jobs)
    __ringo_offer_flags_options -1

    # Offer option value completions
    case "${prev}" in
    '-o'|'--output')
        return
        ;;
    '--output-dir')
        return
        ;;
    '--jobs')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    *)
        __ringo_add_completions -f
        return
        ;;
    esac
}

_ringo_watch() {
    repeating_flags=()
    non_repeating_flags=(--move-originals --once --keep-timestamps --strip-metadata --ocr --no-ocr --json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(-t --to --quality --preset --dpi --pages --sheet --page-size --fps --max-width --max-duration --audio-bitrate --provider --timeout)
    __ringo_offer_flags_options 1

    # Offer option value completions
    case "${prev}" in
    '-t'|'--to')
        return
        ;;
    '--quality')
        return
        ;;
    '--preset')
        return
        ;;
    '--dpi')
        return
        ;;
    '--pages')
        return
        ;;
    '--sheet')
        return
        ;;
    '--page-size')
        return
        ;;
    '--fps')
        return
        ;;
    '--max-width')
        return
        ;;
    '--max-duration')
        return
        ;;
    '--audio-bitrate')
        return
        ;;
    '--provider')
        return
        ;;
    '--timeout')
        return
        ;;
    esac

    # Offer positional completions
    case "${positional_number}" in
    1)
        __ringo_add_completions -d
        return
        ;;
    esac
}

_ringo_batch() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=(--manifest)
    __ringo_offer_flags_options 0

    # Offer option value completions
    case "${prev}" in
    '--manifest')
        return
        ;;
    esac
}

_ringo_providers() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 1
}

_ringo_settings() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 3
}

_ringo_version() {
    repeating_flags=()
    non_repeating_flags=(--json --events --no-network --version -h --help)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options 0
}

_ringo_help() {
    repeating_flags=()
    non_repeating_flags=(--version)
    repeating_options=()
    non_repeating_options=()
    __ringo_offer_flags_options -1
}

complete -o filenames -F _ringo ringo
