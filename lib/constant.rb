module Constant
	Result = Struct.new(:url, :user, :cred)
	SFTP = Result.new(Rails.env == 'production' ? 'csv.example.com/endpoint/' : '0.0.0.0:2020', "some-ftp-user", :keys => ["path-to-credentials"])
	SFTP_SERVER = [
	  SFTP.url,
	  SFTP.user,
	  SFTP.cred
	].freeze
end