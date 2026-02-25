# --- Box drawing ---

const BOX_TL = "╭"
const BOX_TR = "╮"
const BOX_BL = "╰"
const BOX_BR = "╯"
const BOX_H  = "─"
const BOX_V  = "│"

"""Draw a box with title and content lines."""
function box(title::String, lines::Vector{String}; width::Int = 72)
    buf = IOBuffer()
    inner = width - 4  # 2 for border + 2 for padding

    # Top border with title
    title_segment = "─ $title "
    remaining = width - 2 - length(title_segment)
    println(buf, " $BOX_TL$title_segment$(BOX_H ^ max(0, remaining))$BOX_TR")

    # Content
    for line in lines
        padded = rpad(line, inner)
        println(buf, " $BOX_V  $(padded[1:min(end, inner)])  $BOX_V")
    end

    # Bottom border
    println(buf, " $BOX_BL$(BOX_H ^ (width - 2))$BOX_BR")

    String(take!(buf))
end

# --- Progress bar ---

"""Render a progress bar: ━━━━━━━━━━━━━━━  5/10  50%"""
function progress_bar(completed::Int, total::Int; width::Int = 30)
    pct = total > 0 ? completed / total : 0.0
    filled = round(Int, pct * width)
    bar = "━" ^ filled * " " ^ (width - filled)
    "$bar  $completed/$total  $(round(Int, pct * 100))%"
end

# --- Spinner ---

const SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧']

"""Get a spinner frame by index (wraps around)."""
spinner_frame(i::Int) = SPINNER_FRAMES[mod(i, length(SPINNER_FRAMES)) + 1]

# --- Bar chart ---

const BAR_CHARS = ['▏', '▎', '▍', '▌', '▋', '▊', '▉', '█']

"""Render a proportional bar chart."""
function bar_chart(value::Number, max_value::Number; width::Int = 10)
    max_value <= 0 && return " " ^ width
    ratio = clamp(value / max_value, 0.0, 1.0)
    total_eighths = round(Int, ratio * width * 8)
    full_blocks = div(total_eighths, 8)
    remainder = mod(total_eighths, 8)

    result = "█" ^ full_blocks
    if remainder > 0
        result *= string(BAR_CHARS[remainder])
    end
    rpad(result, width)
end

# --- Sparkline ---

const SPARK_CHARS = collect("▁▂▃▄▅▆▇█")

"""Render a sparkline from a vector of values."""
function sparkline(values::Vector{<:Number})
    isempty(values) && return ""
    lo, hi = extrema(values)
    range = hi - lo
    range == 0 && return string(SPARK_CHARS[4]) ^ length(values)

    String(map(values) do v
        idx = clamp(round(Int, (v - lo) / range * 7) + 1, 1, 8)
        SPARK_CHARS[idx]
    end)
end

# --- Dot leader ---

"""Connect a left label to a right value with dots."""
function dot_leader(left::String, right::String; width::Int = 60)
    dots_needed = width - length(left) - length(right) - 2
    dots_needed = max(dots_needed, 1)
    "$left $(repeat('·', dots_needed)) $right"
end

# --- Formatting helpers ---

"""Format a duration in seconds to human-readable string."""
function format_duration(seconds::Float64)
    if seconds < 0.01
        "$(round(Int, seconds * 1000))ms"
    elseif seconds < 60
        "$(round(seconds; digits=2))s"
    else
        m = floor(Int, seconds / 60)
        s = round(Int, seconds - m * 60)
        "$(m)m $(lpad(string(s), 2, '0'))s"
    end
end

"""Format bytes to human-readable string."""
function format_bytes(bytes::Number)
    if bytes < 1024
        "$(round(Int, bytes)) B"
    elseif bytes < 1024^2
        "$(round(bytes / 1024; digits=1)) KB"
    elseif bytes < 1024^3
        "$(round(bytes / 1024^2; digits=1)) MB"
    else
        "$(round(bytes / 1024^3; digits=1)) GB"
    end
end

"""Return a color symbol based on duration thresholds."""
function color_for_duration(seconds::Float64;
    fast::Float64 = 0.1, medium::Float64 = 1.0)
    seconds < fast ? :green : seconds < medium ? :yellow : :red
end
