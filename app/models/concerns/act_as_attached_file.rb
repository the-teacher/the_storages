# encoding: UTF-8
module ActAsAttachedFile
  extend ActiveSupport::Concern

  included do
    IMAGE_EXTS = %w[jpg jpeg pjpeg png gif bmp]
    IMAGE_CONTENT_TYPES = IMAGE_EXTS.map{ |e| "image/#{e}" }

    belongs_to :user
    belongs_to :storage, polymorphic: true
    acts_as_nested_set scope: [:user_id, :storage_id, :storage_type]
    
    before_validation :generate_file_name, on: :create
    # after_create   :recalculate_storage_counters
    # after_update   :recalculate_storage_counters
    # before_destroy :recalculate_storage_counters

    scope :images, ->{ where(attachment_content_type: IMAGE_CONTENT_TYPES)  }

    # IMAGE PROCESSING HOOKS
    def set_processing_flag; self.processing = :processing; end
    before_create :set_processing_flag,      if: ->(attachment){ attachment.is_image? }
    after_create  :delayed_image_processing, if: ->(attachment){ attachment.is_image? }
    #~ IMAGE PROCESSING HOOKS

    has_attached_file :attachment,
                      default_url: "/uploads/default/:style/missing.jpg",
                      url:         "/uploads/storages/:storage_type/:storage_id/:style-:filename"

    validates_attachment_size :attachment,
      in: 10.bytes..5.megabytes,
      message: I18n.translate('the_storages.validation.attachment_file_size')

    validates :attachment_file_name,
      uniqueness: {
        scope: [:user_id, :storage_type, :storage_id],
        message: I18n.translate('the_storages.validation.uniq_attachment_file_name')
      }
  end

  # HELPERS
  def title
    attachment_file_name
  end

  def file_name
    File.basename attachment_file_name.downcase, file_extension
  end

  def file_extension
    ext = File.extname(attachment_file_name).downcase
    ext.slice!(0)
    @extension ||= ext
  end

  def content_type
    attachment_content_type
  end

  def mb_size
    sprintf("%.3f", attachment_file_size.to_f/1.megabyte.to_f) + " MB"
  end

  def path style = nil
    attachment.path(style)
  end

  def url style = nil, opts = {}
    url = attachment.url(style, opts)
    return url unless opts[:nocache]
    rnd = (rand*1000000).to_i.to_s
    url =~ /\?/ ? (url + rnd) : (url + '?' + rnd)
  end

  # BASE HELPERS
  def is_image?
    IMAGE_EXTS.include? file_extension
  end

  def generate_file_name
    fname = Russian::translit(file_name).gsub('_','-').parameterize
    self.attachment.instance_write :file_name, "#{fname}.#{file_extension}"
  end

  # CALLBACKS
  def recalculate_storage_counters
    storage.recalculate_storage_counters
  end

  # DELAYED JOB
  def delayed_image_processing
    job = DelayedImageProcessor.new(self)
    Delayed::Job.enqueue job, queue: :image_processing, run_at: Proc.new { 10.seconds.from_now }
  end

  # IMAGE PROCESSING

  def landscape? image
    image[:width] > image[:height]
  end

  def portrait? image
    image[:width] < image[:height]
  end

  def create_empty_png
    dir_path  = "#{Rails.root.to_s}/tmp/images"
    empty_png = "#{dir_path}/empty.png"

    FileUtils.mkdir_p dir_path
    Cocaine::CommandLine.new("convert", "-size 800x50 xc:transparent #{empty_png}").run
  end

  def create_watermark_text
    create_empty_png

    dir_path  = "#{Rails.root.to_s}/tmp/images"
    empty_png = "#{dir_path}/empty.png"
    title_png = "#{dir_path}/title.png"
    font      = "#{dir_path}/georgia_italic.ttf" # Times-Roman
    
    title = "Открытая кухня Анны Нечаевой"
    fs    = "-font #{font} -pointsize 20"

    bt       = "fill black text 0,12 'open-cook.ru   #{title}'"
    wt       = "fill white text 1,11 'open-cook.ru   #{title}'"
    put_text = "-draw \"gravity south #{bt} #{wt}\""

    Cocaine::CommandLine.new("convert", "#{empty_png} #{fs} #{put_text} -trim #{title_png}").run
  end


  def build_correct_preview
    main     = path :main
    preview  = path :preview
    
    image = MiniMagick::Image.open main

    min_size = image[:width]
    shift    = { x: 0, y: 0}
    
    if landscape?(image)
      min_size  = image[:height]
      shift[:x] = (image[:width] - min_size) / 2
    elsif portrait?(image)
      min_size = image[:width]
      shift[:y] = (image[:height] - min_size) / 2
    end    
    
    x0 = shift[:x]
    y0 = shift[:y]
    w  = h = min_size

    image.crop "#{w}x#{h}+#{x0}+#{y0}"
    image.resize "100x100!"
    image.write preview
  end

  def build_main_image
    src  = path
    main = path :main

    image = MiniMagick::Image.open src
    image.auto_orient
    landscape?(image) ? image.resize('800x') : image.resize('x800') if image[:width] > 800
    image.strip
    image.write main
  end

  def build_base_images
    # file path
    src  = path
    main = path :main

    # main
    build_main_image

    # preview
    build_correct_preview

    # delete source
    image = MiniMagick::Image.open main
    image.write src

    # set process state
    src_size = File.size?(src)
    update(processing: :finished, attachment_file_size: src_size)
  end

  # IMAGE ROTATION
  def image_rotate angle
    src      = path
    main     = path :main
    preview  = path :preview

    # main
    image = MiniMagick::Image.open src
    image.rotate angle
    image.write src
    image.write main

    # preview
    image = MiniMagick::Image.open main
    image.resize "100x100!"
    image.write preview
  end

  def rotate_left
    image_rotate "-90"
  end

  def rotate_right
    image_rotate "90"
  end

  # IMAGE CROP
  def crop_image name = :cropped_image, x0 = 0, y0 = 0, w = 100, h = 100, img_w = nil
    src      = path
    main     = path :main
    cropped  = path name

    image = MiniMagick::Image.open main
    
    img_w ||= image[:width]
    scale   = image[:width].to_f/img_w.to_f

    w = (w.to_f * scale).to_i
    h = (h.to_f * scale).to_i

    x_shift = (x_shift.to_f * scale).to_i
    y_shift = (y_shift.to_f * scale).to_i

    image.crop "#{w}x#{h}+#{x0}+#{y0}"
    image.write cropped
  end
end