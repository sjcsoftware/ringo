#compdef ringo

__ringo_complete() {
    local -ar non_empty_completions=("${@:#(|:*)}")
    local -ar empty_completions=("${(M)@:#(|:*)}")
    _describe -V '' non_empty_completions -- empty_completions -P $'\'\''
}

__ringo_custom_complete() {
    local -a completions
    completions=("${(@f)"$("${command_name}" "${@}" "${command_line[@]}")"}")
    if [[ "${#completions[@]}" -gt 1 ]]; then
        __ringo_complete "${completions[@]:0:-1}"
    fi
}

__ringo_cursor_index_in_current_word() {
    if [[ -z "${QIPREFIX}${IPREFIX}${PREFIX}" ]]; then
        printf 0
    else
        printf %s "${#${(z)LBUFFER}[-1]}"
    fi
}

_ringo() {
    emulate -RL zsh -G
    setopt extendedglob nullglob numericglobsort
    unsetopt aliases banghist

    local -xr SAP_SHELL=zsh
    local -x SAP_SHELL_VERSION
    SAP_SHELL_VERSION="$(builtin emulate zsh -c 'printf %s "${ZSH_VERSION}"')"
    local -r SAP_SHELL_VERSION

    local context state state_descr line
    local -A opt_args

    local -r command_name="${words[1]}"
    local -ar command_line=("${words[@]}")
    local -ir current_word_index="$((CURRENT - 1))"

    local -i ret=1
    local -ar arg_specs=(
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
        '(-): :->command'
        '(-)*:: :->arg'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0
    case "${state}" in
    command)
        local -ar subcommands=(
            'convert:Convert files to another format. Outputs go next to each source.'
            'plan:Explain how a conversion would run: provider, fidelity, limits, output path.'
            'formats:List every format in the catalog with its role (input-only, export-only, both).'
            'capabilities:List directed conversion edges with provider, fidelity and availability.'
            'inspect:Detect a file'\''s real type and list what it can become and which tools apply.'
            'tools:List file tools with parameters and CLI usage.'
            'compress:Make files smaller: lossy re-encoding, lossless optimization, or a ZIP for other files.'
            'metadata:Show, remove or edit metadata.'
            'edit:Lightweight edits: rotate, flip, resize, trim, PDF pages, merge.'
            'crop:Crop images, PDF pages or video.'
            'annotate:Draw markup on images or PDFs from a JSON spec.'
            'redact:Irreversibly black out text or regions in PDFs and images, then verify.'
            'archive:Pack files and folders into ZIP, TAR, TAR.GZ or GZIP.'
            'extract:Safely extract ZIP, TAR, TAR.GZ, GZIP or RAR into a sibling folder.'
            'watch:Convert files that appear in a folder, until stopped with Ctrl-C.'
            'batch:Run several commands from a JSON manifest and report every result.'
            'providers:List conversion providers and whether they are installed.'
            'settings:Read or change settings shared with Ringo.app.'
            'version:Print version and schema information.'
            'help:Show subcommand help information.'
        )
        _describe -V subcommand subcommands && ret=0
        ;;
    arg)
        case "${words[1]}" in
        convert|plan|formats|capabilities|inspect|tools|compress|metadata|edit|crop|annotate|redact|archive|extract|watch|batch|providers|settings|version|help)
            "_ringo_${words[1]}" && ret=0
            ;;
        esac
        ;;
    esac

    return "${ret}"
}

_ringo_convert() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-t --to)'{-t,--to}'[Target format (png, webp, mp4, docx, … see `ringo formats`).]:to:'
        '--quality[Lossy quality 1–100 (default 85).]:quality:'
        '--preset[Named preset (high, balanced, small).]:preset:'
        '--dpi[Raster DPI for PDF/slide page export (default 300).]:dpi:'
        '--pages[Pages or slides, 1-based\: 1-3,7 (default\: all).]:pages:'
        '--sheet[Spreadsheet sheet\: name, number, or '\''all'\'' (default\: first).]:sheet:'
        '--page-size[Page size for → PDF\: fit, a4, letter.]:page-size:'
        '--keep-timestamps[Subtitles → TXT\: keep timestamps.]'
        '--fps[GIF frames per second (default 12).]:fps:'
        '--max-width[GIF/SVG width bound in pixels.]:max-width:'
        '--max-duration[GIF maximum duration in seconds (default 15).]:max-duration:'
        '--audio-bitrate[Audio bitrate in kbps.]:audio-bitrate:'
        '--provider[Force a provider (see `ringo providers`).]:provider:'
        '--timeout[Seconds before an external tool is stopped (default 1800).]:timeout:'
        '--strip-metadata[Remove metadata from the output where the format allows.]'
        '--ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '--no-ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_plan() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-t --to)'{-t,--to}'[Target format.]:to:'
        '--quality[Lossy quality 1–100 (default 85).]:quality:'
        '--preset[Named preset (high, balanced, small).]:preset:'
        '--dpi[Raster DPI for PDF/slide page export (default 300).]:dpi:'
        '--pages[Pages or slides, 1-based\: 1-3,7 (default\: all).]:pages:'
        '--sheet[Spreadsheet sheet\: name, number, or '\''all'\'' (default\: first).]:sheet:'
        '--page-size[Page size for → PDF\: fit, a4, letter.]:page-size:'
        '--keep-timestamps[Subtitles → TXT\: keep timestamps.]'
        '--fps[GIF frames per second (default 12).]:fps:'
        '--max-width[GIF/SVG width bound in pixels.]:max-width:'
        '--max-duration[GIF maximum duration in seconds (default 15).]:max-duration:'
        '--audio-bitrate[Audio bitrate in kbps.]:audio-bitrate:'
        '--provider[Force a provider (see `ringo providers`).]:provider:'
        '--timeout[Seconds before an external tool is stopped (default 1800).]:timeout:'
        '--strip-metadata[Remove metadata from the output where the format allows.]'
        '--ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '--no-ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_formats() {
    local -i ret=1
    local -ar arg_specs=(
        '--category[Only this category (image, audio, video, pdf, document, slides, spreadsheet, subtitle, archive, …).]:category:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_capabilities() {
    local -i ret=1
    local -ar arg_specs=(
        '--from[Only edges from this format.]:from:'
        '--to[Only edges to this format.]:to:'
        '--all[Every provider for every edge (default\: the best provider per edge).]'
        '--available[Only edges that can run on this Mac now.]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_inspect() {
    local -i ret=1
    local -ar arg_specs=(
        ':file:_files'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_tools() {
    local -i ret=1
    local -ar arg_specs=(
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_compress() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--preset[lossless, high, balanced, small, tiny.]:preset:'
        '--target-size[Images\: aim for this size (e.g. 500KB).]:target-size:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_metadata() {
    local -i ret=1
    local -ar arg_specs=(
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
        '(-): :->command'
        '(-)*:: :->arg'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0
    case "${state}" in
    command)
        local -ar subcommands=(
            'show:List metadata fields (sensitive ones are flagged).'
            'strip:Write a copy without metadata (images: pixels untouched).'
            'set:Write a copy with edited fields.'
        )
        _describe -V subcommand subcommands && ret=0
        ;;
    arg)
        case "${words[1]}" in
        show|strip|set)
            "_ringo_metadata_${words[1]}" && ret=0
            ;;
        esac
        ;;
    esac

    return "${ret}"
}

_ringo_metadata_show() {
    local -i ret=1
    local -ar arg_specs=(
        ':file:_files'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_metadata_strip() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--location-only[Remove only GPS/location data.]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_metadata_set() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '*--field[name=value, repeatable (title, description, artist, copyright, keywords, author, …).]:field:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit() {
    local -i ret=1
    local -ar arg_specs=(
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
        '(-): :->command'
        '(-)*:: :->arg'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0
    case "${state}" in
    command)
        local -ar subcommands=(
            'rotate:Rotate images clockwise (JPEG/HEIC: lossless).'
            'flip:Mirror images.'
            'resize:Resize images.'
            'trim:Cut audio or video to a time range (no re-encode).'
            'extract-audio:Save a video'\''s audio track as M4A.'
            'mute:Remove a video'\''s audio.'
            'pdf:PDF page operations (choose one).'
            'merge:Combine PDFs and images, in the given order, into one PDF.'
        )
        _describe -V subcommand subcommands && ret=0
        ;;
    arg)
        case "${words[1]}" in
        rotate|flip|resize|trim|extract-audio|mute|pdf|merge)
            "_ringo_edit_${words[1]}" && ret=0
            ;;
        esac
        ;;
    esac

    return "${ret}"
}

_ringo_edit_rotate() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--degrees[90, 180, 270 or negative.]:degrees:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_flip() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--vertical[Flip top to bottom (default\: left to right).]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_resize() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--percent[Scale percent.]:percent:'
        '--max[Fit the long edge to this many pixels.]:max:'
        '--width:width:'
        '--height:height:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_trim() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--start[Start (seconds or hh\:mm\:ss.sss).]:start:'
        '--end[End (default\: end of file).]:end:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_extract-audio() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_mute() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_pdf() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--rotate[Rotate pages clockwise by degrees (with --pages to limit).]:rotate:'
        '--pages[Pages to rotate (default all).]:pages:'
        '--delete[Delete these pages\: 2,5-7.]:delete:'
        '--extract[Keep only these pages.]:extract:'
        '--order[New page order\: 3,1,2.]:order:'
        '--reverse[Reverse page order.]'
        '--split[One PDF per page.]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_edit_merge() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_crop() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--rect[x,y,width,height (top-left origin; pixels, or PDF points).]:rect:'
        '--aspect[Centered crop to an aspect ratio\: 1\:1, 4\:3, 16\:9 …]:aspect:'
        '--normalized[--rect values are 0…1 fractions.]'
        '--pages[PDF pages to crop (default all).]:pages:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--in-place[Replace the source file instead of writing a sibling (not reversible).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_annotate() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--spec[Annotation JSON file.]:spec:'
        '--flatten[PDF\: draw into page content instead of adding editable annotations.]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_redact() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--regions[JSON file with regions.]:regions:'
        '*--text[Text to find and redact (repeatable).]:text:'
        '*--pattern[Built-in pattern\: email, phone, credit-card, ssn, url, ipv4 (repeatable).]:pattern:'
        '--case-sensitive[Match text case-sensitively.]'
        '--dpi[PDF rasterization DPI (default 200).]:dpi:'
        '--no-ocr[Do not OCR images or scanned pages to find text.]'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_archive() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '--format[zip, tar, tgz, gzip.]:format:'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_extract() {
    local -i ret=1
    local -ar arg_specs=(
        '*:inputs:_files'
        '(-o --output)'{-o,--output}'[Exact output path (single input only).]:output:'
        '--output-dir[Write outputs here instead of next to each source.]:output-dir:'
        '--overwrite[Replace an existing file at the output name (never the source).]'
        '--dry-run[Show what would be written without writing anything.]'
        '--jobs[Maximum files processed at once (default from settings\: 2).]:jobs:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_watch() {
    local -i ret=1
    local -ar arg_specs=(
        ':folder:_files -/'
        '(-t --to)'{-t,--to}'[Target format.]:to:'
        '--move-originals[Move each converted original into an Originals subfolder.]'
        '--once[Process files already in the folder, then exit (no watching).]'
        '--quality[Lossy quality 1–100 (default 85).]:quality:'
        '--preset[Named preset (high, balanced, small).]:preset:'
        '--dpi[Raster DPI for PDF/slide page export (default 300).]:dpi:'
        '--pages[Pages or slides, 1-based\: 1-3,7 (default\: all).]:pages:'
        '--sheet[Spreadsheet sheet\: name, number, or '\''all'\'' (default\: first).]:sheet:'
        '--page-size[Page size for → PDF\: fit, a4, letter.]:page-size:'
        '--keep-timestamps[Subtitles → TXT\: keep timestamps.]'
        '--fps[GIF frames per second (default 12).]:fps:'
        '--max-width[GIF/SVG width bound in pixels.]:max-width:'
        '--max-duration[GIF maximum duration in seconds (default 15).]:max-duration:'
        '--audio-bitrate[Audio bitrate in kbps.]:audio-bitrate:'
        '--provider[Force a provider (see `ringo providers`).]:provider:'
        '--timeout[Seconds before an external tool is stopped (default 1800).]:timeout:'
        '--strip-metadata[Remove metadata from the output where the format allows.]'
        '--ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '--no-ocr[OCR scanned PDF pages with the local Vision framework (default\: only when the PDF has no text).]'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_batch() {
    local -i ret=1
    local -ar arg_specs=(
        '--manifest[Manifest JSON file.]:manifest:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_providers() {
    local -i ret=1
    local -ar arg_specs=(
        ':action:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_settings() {
    local -i ret=1
    local -ar arg_specs=(
        ':action:'
        ':key:'
        ':value:'
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_version() {
    local -i ret=1
    local -ar arg_specs=(
        '--json[Print one JSON document (schema ringo/1) on stdout.]'
        '--events[Stream NDJSON progress events on stderr.]'
        '--no-network[Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.]'
        '--version[Show the version.]'
        '(-h --help)'{-h,--help}'[Show help information.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

_ringo_help() {
    local -i ret=1
    local -ar arg_specs=(
        '*:subcommands:'
        '--version[Show the version.]'
    )
    _arguments -w -s -S : "${arg_specs[@]}" && ret=0

    return "${ret}"
}

if [[ "${funcstack[1]}" = _ringo ]]; then
    _ringo "${@}"
else
    compdef _ringo ringo
fi
