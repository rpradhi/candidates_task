# encoding: utf-8
require 'net/sftp'
require 'iconv'
require 'csv'
require 'active_support/all'
before = $LOADED_FEATURES.dup
require 'constant'
require_relative './file_import_builder'
require_relative './transaction_error'

class CsvExporter
  extend FileImportBuilder

  @errors = []

  class << self
    def transfer_and_import(send_email = true)
      @errors = []

      local_files = transfer_from_remote
      import_from_local_files(local_files, send_email)
    end

    def transfer_from_remote
      build_local_folders
      local_files = []
      Net::SFTP.start(*Constant::SFTP_SERVER) do |sftp|
        available_entries(sftp).each do |entry|
          sftp.download!(remote_path(entry), local_path(entry))
          sftp.remove!(remote_path(entry) + '.start')

          local_files << entry
        end
      end
    end

    def build_local_folders
      FileUtils.mkdir_p "#{Rails.root}/private/data"
      FileUtils.mkdir_p "#{Rails.root}/private/data/download"
    end

    def available_entries(sftp)
      remote_files = sftp.dir.entries('/data/files/csv').map(&:name)
      remote_files.select do |filename|
        filename[-4, 4] == '.csv' &&
          remote_files.include?(filename + '.start')
      end.sort
    end

    private

    def upload_error_file(entry, result)
      FileUtils.mkdir_p "#{Rails.root}/private/data/upload"
      error_file = "#{Rails.root}/private/data/upload/#{entry}"
      File.open(error_file, 'w') do |f|
        f.write(result)
      end
      Net::SFTP.start(*Constant::SFTP_SERVER) do |sftp|
        sftp.upload!(error_file, "/data/files/batch_processed/#{entry}")
      end
    end
  end
end

