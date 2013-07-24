# encoding: UTF-8
module StorageImageProcessing
  include WatermarkFu
  include ImageManipulation

  def draw_watermark
    return false unless need_watermark?
    build_watermarks
    put_watermark_on_base_image
  end

  def build_base_images
    resize_src_image
    refresh_base_image

    # set process state
    src_size = File.size?(path)
    update(processing: :finished, attachment_file_size: src_size)
  end

  def create_img_dir_path path
    _path = path.split('/')[0...-1].join('/')
    FileUtils.mkdir_p _path
  end

  # IMAGE PROCESSING
  def prepare_image src, dest, larger_side
    image = MiniMagick::Image.open src
    image.auto_orient
    resize_to_larger_side(image, larger_side)
    image.strip
    create_img_dir_path(dest)
    image.write(dest)
  end

  def build_square_image src, dest, side = 100
    image = MiniMagick::Image.open src

    min_size = image[:width]
    shift    = { x: 0, y: 0}
    
    if landscape?(image)
      min_size  = image[:height]
      shift[:x] = (image[:width] - min_size) / 2
    elsif portrait?(image)
      min_size  = image[:width]
      shift[:y] = (image[:height] - min_size) / 2
    end    
    
    x0 = shift[:x]
    y0 = shift[:y]
    w  = h = min_size

    image.crop "#{w}x#{h}+#{x0}+#{y0}"
    image.resize "#{side}x#{side}!"

    create_img_dir_path(dest)
    image.write dest
  end

  def build_correct_preview
    src      = path
    preview  = path :preview
    build_square_image(src, preview, 100)
  end

  def build_base_image
    src  = path
    base = path :base
    prepare_image(src, base, TheStorages.config.base_larger_side)
  end

  def refresh_base_image
    build_base_image
    build_correct_preview
    draw_watermark
  end

  def resize_src_image
    src = path
    prepare_image(src, src, TheStorages.config.original_larger_side)
  end

  def destroy_processed_files
    base    = path :base
    preview = path :preview

    FileUtils.rm([base, preview], force: true)
  end
end