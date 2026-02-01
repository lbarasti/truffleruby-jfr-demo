# frozen_string_literal: true

require 'chunky_png'

# Image processing jobs - CPU intensive operations for generating and processing images
module ImageJobs
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  # Color constants
  WHITE = [255, 255, 255].freeze
  BLACK = [20, 20, 20].freeze

  # Curated color palettes for generative art
  PALETTES = [
    [[255, 87, 51], [255, 189, 51], [51, 255, 87], [51, 189, 255], [189, 51, 255]],  # Neon
    [[30, 30, 40], [255, 71, 87], [255, 165, 2], [46, 213, 115], [55, 66, 250]],     # Dark vibrant
    [[255, 107, 107], [254, 202, 87], [29, 209, 161], [95, 39, 205], [52, 31, 151]], # Sunset
    [[0, 48, 73], [214, 40, 40], [247, 127, 0], [252, 191, 73], [234, 226, 183]],    # Retro
    [[20, 20, 20], [255, 255, 255], [255, 59, 48], [0, 199, 190], [255, 204, 0]],    # Bold contrast
  ].freeze

  # Read PNG dimensions without full decode
  def self.png_dimensions(io)
    io.rewind
    header = io.read(24)
    return nil if header.nil? || header.bytesize < 24
    return nil unless header.start_with?(PNG_SIGNATURE)
    return nil unless header.byteslice(12, 4) == "IHDR".b

    width = header.byteslice(16, 4).unpack1("N")
    height = header.byteslice(20, 4).unpack1("N")
    [width, height]
  ensure
    io.rewind
  end

  # Generate Mandelbrot fractal - very CPU intensive
  def self.mandelbrot(size: 256, max_iter: 100)
    png = ChunkyPNG::Image.new(size, size, ChunkyPNG::Color::BLACK)

    size.times do |py|
      size.times do |px|
        x0 = (px - size * 0.7) * 3.5 / size
        y0 = (py - size / 2.0) * 3.5 / size

        x = 0.0
        y = 0.0
        iter = 0

        while x * x + y * y <= 4 && iter < max_iter
          xtemp = x * x - y * y + x0
          y = 2 * x * y + y0
          x = xtemp
          iter += 1
        end

        if iter < max_iter
          hue = (iter.to_f / max_iter * 360).to_i
          png[px, py] = hsv_to_rgb(hue, 1.0, 1.0)
        end
      end
    end

    png
  end

  # Generate plasma/noise pattern - CPU intensive
  def self.plasma(size: 256, scale: 0.05)
    png = ChunkyPNG::Image.new(size, size, ChunkyPNG::Color::BLACK)

    size.times do |y|
      size.times do |x|
        # Combine multiple sine waves for plasma effect
        v1 = Math.sin(x * scale)
        v2 = Math.sin(y * scale)
        v3 = Math.sin((x + y) * scale)
        v4 = Math.sin(Math.sqrt(x * x + y * y) * scale)

        v = (v1 + v2 + v3 + v4) / 4.0
        hue = ((v + 1) * 180).to_i

        png[x, y] = hsv_to_rgb(hue, 0.8, 0.9)
      end
    end

    png
  end

  # Apply grayscale filter to uploaded image
  def self.grayscale(png)
    result = ChunkyPNG::Image.new(png.width, png.height)

    png.height.times do |y|
      png.width.times do |x|
        pixel = png[x, y]
        r = ChunkyPNG::Color.r(pixel)
        g = ChunkyPNG::Color.g(pixel)
        b = ChunkyPNG::Color.b(pixel)
        gray = ((r * 0.299 + g * 0.587 + b * 0.114)).to_i
        result[x, y] = ChunkyPNG::Color.rgb(gray, gray, gray)
      end
    end

    result
  end

  # Apply pixelate filter - CPU intensive for small block sizes
  def self.pixelate(png, block_size: 8)
    result = ChunkyPNG::Image.new(png.width, png.height)

    (0...png.height).step(block_size) do |by|
      (0...png.width).step(block_size) do |bx|
        # Average colors in block
        r_sum = g_sum = b_sum = count = 0

        block_size.times do |dy|
          block_size.times do |dx|
            x = bx + dx
            y = by + dy
            next if x >= png.width || y >= png.height

            pixel = png[x, y]
            r_sum += ChunkyPNG::Color.r(pixel)
            g_sum += ChunkyPNG::Color.g(pixel)
            b_sum += ChunkyPNG::Color.b(pixel)
            count += 1
          end
        end

        avg_color = ChunkyPNG::Color.rgb(r_sum / count, g_sum / count, b_sum / count)

        # Fill block with average color
        block_size.times do |dy|
          block_size.times do |dx|
            x = bx + dx
            y = by + dy
            next if x >= png.width || y >= png.height
            result[x, y] = avg_color
          end
        end
      end
    end

    result
  end

  # Edge detection using Sobel operator - CPU intensive
  def self.edge_detect(png)
    result = ChunkyPNG::Image.new(png.width, png.height, ChunkyPNG::Color::BLACK)

    # Sobel kernels
    gx = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
    gy = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]

    (1...png.height - 1).each do |y|
      (1...png.width - 1).each do |x|
        px_gx = py_gy = 0.0

        3.times do |ky|
          3.times do |kx|
            pixel = png[x + kx - 1, y + ky - 1]
            gray = ChunkyPNG::Color.r(pixel) * 0.299 +
                   ChunkyPNG::Color.g(pixel) * 0.587 +
                   ChunkyPNG::Color.b(pixel) * 0.114

            px_gx += gray * gx[ky][kx]
            py_gy += gray * gy[ky][kx]
          end
        end

        magnitude = Math.sqrt(px_gx * px_gx + py_gy * py_gy).to_i
        magnitude = [magnitude, 255].min
        result[x, y] = ChunkyPNG::Color.rgb(magnitude, magnitude, magnitude)
      end
    end

    result
  end

  # Generate geometric generative art with Voronoi cells and shapes - CPU intensive
  def self.generative(size: 512, seed: nil)
    seed ||= Random.new_seed
    rng = Random.new(seed)
    palette = PALETTES[rng.rand(PALETTES.size)]

    # Generate Voronoi seed points
    num_cells = rng.rand(15..40)
    cells = num_cells.times.map do
      {
        x: rng.rand(0...size),
        y: rng.rand(0...size),
        color: palette[rng.rand(palette.size)]
      }
    end

    # Create base image with Voronoi cells
    png = ChunkyPNG::Image.new(size, size)

    size.times do |y|
      size.times do |x|
        # Find nearest cell (Voronoi)
        min_dist = Float::INFINITY
        nearest_cell = cells[0]

        cells.each do |cell|
          dist = (x - cell[:x])**2 + (y - cell[:y])**2
          if dist < min_dist
            min_dist = dist
            nearest_cell = cell
          end
        end

        r, g, b = nearest_cell[:color]
        png[x, y] = ChunkyPNG::Color.rgb(r, g, b)
      end
    end

    # Draw geometric shapes on top
    num_shapes = rng.rand(8..20)
    num_shapes.times do
      shape_type = rng.rand(4)
      color = palette[rng.rand(palette.size)]
      stroke_color = rng.rand < 0.5 ? WHITE : BLACK

      case shape_type
      when 0 # Filled triangle
        draw_triangle(png, rng, size, color, stroke_color)
      when 1 # Circle with stroke
        draw_circle(png, rng, size, color, stroke_color)
      when 2 # Rectangle
        draw_rectangle(png, rng, size, color, stroke_color)
      when 3 # Line pattern
        draw_lines(png, rng, size, stroke_color)
      end
    end

    # Add some small accent dots
    num_dots = rng.rand(20..50)
    num_dots.times do
      cx = rng.rand(0...size)
      cy = rng.rand(0...size)
      radius = rng.rand(3..8)
      color = rng.rand < 0.5 ? WHITE : BLACK

      draw_filled_circle(png, cx, cy, radius, color)
    end

    png
  end

  # ---------------------------------------------------------------------------
  # Drawing Primitives (used by generative art)
  # ---------------------------------------------------------------------------

  # Draw a random triangle
  def self.draw_triangle(png, rng, size, fill_color, stroke_color)
    # Generate 3 random points
    points = 3.times.map { [rng.rand(0...size), rng.rand(0...size)] }

    # Fill triangle using scanline
    fill_triangle(png, points, fill_color)

    # Draw edges
    stroke = ChunkyPNG::Color.rgb(*stroke_color)
    3.times do |i|
      draw_line(png, points[i][0], points[i][1], points[(i + 1) % 3][0], points[(i + 1) % 3][1], stroke)
    end
  end

  # Fill a triangle using scanline algorithm
  def self.fill_triangle(png, points, color)
    # Sort points by y coordinate
    sorted = points.sort_by { |p| p[1] }
    x0, y0 = sorted[0]
    x1, y1 = sorted[1]
    x2, y2 = sorted[2]

    fill = ChunkyPNG::Color.rgb(*color)

    # Interpolation helper
    interpolate = ->(y, xa, ya, xb, yb) {
      return xa if ya == yb
      xa + (xb - xa) * (y - ya) / (yb - ya)
    }

    (y0.to_i..y2.to_i).each do |y|
      next if y < 0 || y >= png.height

      if y < y1
        # Upper part
        next if y1 == y0
        x_start = interpolate.call(y.to_f, x0.to_f, y0.to_f, x2.to_f, y2.to_f)
        x_end = interpolate.call(y.to_f, x0.to_f, y0.to_f, x1.to_f, y1.to_f)
      else
        # Lower part
        next if y2 == y1
        x_start = interpolate.call(y.to_f, x0.to_f, y0.to_f, x2.to_f, y2.to_f)
        x_end = interpolate.call(y.to_f, x1.to_f, y1.to_f, x2.to_f, y2.to_f)
      end

      x_start, x_end = [x_start, x_end].minmax
      (x_start.to_i..x_end.to_i).each do |x|
        png[x, y] = fill if x >= 0 && x < png.width
      end
    end
  end

  # Draw a filled circle with stroke outline
  def self.draw_circle(png, rng, size, fill_color, stroke_color)
    cx = rng.rand(size * 0.1..size * 0.9).to_i
    cy = rng.rand(size * 0.1..size * 0.9).to_i
    radius = rng.rand(size * 0.05..size * 0.2).to_i

    # Fill
    draw_filled_circle(png, cx, cy, radius, fill_color)

    # Stroke
    stroke = ChunkyPNG::Color.rgb(*stroke_color)
    draw_circle_outline(png, cx, cy, radius, stroke, 2)
  end

  # Draw a filled circle
  def self.draw_filled_circle(png, cx, cy, radius, color)
    fill = ChunkyPNG::Color.rgb(*color)

    (-radius..radius).each do |dy|
      (-radius..radius).each do |dx|
        if dx * dx + dy * dy <= radius * radius
          x = cx + dx
          y = cy + dy
          png[x, y] = fill if x >= 0 && x < png.width && y >= 0 && y < png.height
        end
      end
    end
  end

  # Draw circle outline
  def self.draw_circle_outline(png, cx, cy, radius, color, thickness)
    (0..360).step(1) do |angle|
      rad = angle * Math::PI / 180
      thickness.times do |t|
        r = radius - t
        x = (cx + r * Math.cos(rad)).to_i
        y = (cy + r * Math.sin(rad)).to_i
        png[x, y] = color if x >= 0 && x < png.width && y >= 0 && y < png.height
      end
    end
  end

  # Draw a rectangle
  def self.draw_rectangle(png, rng, size, fill_color, stroke_color)
    x1 = rng.rand(0...size)
    y1 = rng.rand(0...size)
    w = rng.rand(size * 0.05..size * 0.3).to_i
    h = rng.rand(size * 0.05..size * 0.3).to_i
    x2 = [x1 + w, size - 1].min
    y2 = [y1 + h, size - 1].min

    fill = ChunkyPNG::Color.rgb(*fill_color)
    stroke = ChunkyPNG::Color.rgb(*stroke_color)

    # Fill
    (y1..y2).each do |y|
      (x1..x2).each do |x|
        png[x, y] = fill if x >= 0 && x < png.width && y >= 0 && y < png.height
      end
    end

    # Stroke
    draw_line(png, x1, y1, x2, y1, stroke)
    draw_line(png, x2, y1, x2, y2, stroke)
    draw_line(png, x2, y2, x1, y2, stroke)
    draw_line(png, x1, y2, x1, y1, stroke)
  end

  # Draw random lines
  def self.draw_lines(png, rng, size, color)
    stroke = ChunkyPNG::Color.rgb(*color)
    num_lines = rng.rand(3..8)

    num_lines.times do
      x1 = rng.rand(0...size)
      y1 = rng.rand(0...size)
      x2 = rng.rand(0...size)
      y2 = rng.rand(0...size)
      draw_line(png, x1, y1, x2, y2, stroke)
    end
  end

  # Bresenham's line algorithm
  def self.draw_line(png, x1, y1, x2, y2, color)
    x1, y1, x2, y2 = x1.to_i, y1.to_i, x2.to_i, y2.to_i
    dx = (x2 - x1).abs
    dy = (y2 - y1).abs
    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1
    err = dx - dy

    loop do
      png[x1, y1] = color if x1 >= 0 && x1 < png.width && y1 >= 0 && y1 < png.height

      break if x1 == x2 && y1 == y2

      e2 = 2 * err
      if e2 > -dy
        err -= dy
        x1 += sx
      end
      if e2 < dx
        err += dx
        y1 += sy
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Color Helpers
  # ---------------------------------------------------------------------------

  # HSV to RGB conversion
  def self.hsv_to_rgb(h, s, v)
    c = v * s
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = v - c

    r, g, b = case h
              when 0...60 then [c, x, 0]
              when 60...120 then [x, c, 0]
              when 120...180 then [0, c, x]
              when 180...240 then [0, x, c]
              when 240...300 then [x, 0, c]
              else [c, 0, x]
              end

    ChunkyPNG::Color.rgb(
      ((r + m) * 255).to_i,
      ((g + m) * 255).to_i,
      ((b + m) * 255).to_i
    )
  end
end
