# frozen_string_literal: true

require 'chunky_png'

# Image processing jobs - CPU intensive operations for generating and processing images
module ImageJobs
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

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

  # HSV to RGB helper
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
