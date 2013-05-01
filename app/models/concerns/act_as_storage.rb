module ActAsStorage
  extend ActiveSupport::Concern

  included do
    has_many :attached_files, as: :storage

    before_update :recalculate_storage_counters
    after_update  :recalculate_user_counters
    after_destroy :recalculate_user_counters
  end

  def recalculate_storage_counters
    # puts "recalculate_files_data"
    # sum   = 0
    # files = self.uploaded_files.active

    # files.each{ |f| sum += f.file_file_size }
    # self.files_size  = sum
    # self.files_count = files.size
  end

  def recalculate_user_counters
    # puts "recalculate_files_data_for_user"
    #   user        = self.user
    #   storages    = user.storages.active | user.recipes.active | user.pages.active | user.articles.active
    #   files_size  = 0
    #   files_count = 0

    #   storages.each do |s|
    #     files_size  += s.files_size
    #     files_count += s.files_count
    #   end

    #   user.files_size  = files_size
    #   user.files_count = files_count
    #   user.save(:validation => false)
  end
end