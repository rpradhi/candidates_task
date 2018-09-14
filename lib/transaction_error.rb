class TransactionError
	attr_accessor :status, :message, :type, :code, :http_code, :content

	def initialize(message, type)
		@status = "ERROR"
		@message = message
		@type = type
	end

	def self.validate_import_row(row)
		TransactionError.new("#{row['ACTIVITY_ID']}: UMSATZ_KEY #{row['UMSATZ_KEY']} is not allowed", 'error')
	end

	def self.transaction_type_error(row)
		TransactionError.new("#{row['ACTIVITY_ID']}: Transaction type not found", 'error')
	end

	def self.file_import_error(entry, result)
		TransactionError.new("Import of the file #{entry} failed with errors:\n#{result}", 'error')
	end

	def self.exception_error(row, e)
		TransactionError.new("#{row['ACTIVITY_ID']}: #{e}", 'error')
	end

	def self.get_sender_error(row)
		TransactionError.new("#{row['ACTIVITY_ID']}: Account #{row['SENDER_KONTO']} not found", 'error')
	end

	def self.account_transfer_error(row, state=nil)
		if (state!=nil)
			TransactionError.new("#{row['ACTIVITY_ID']}: AccountTransfer state \
								 expected 'pending' but was '#{state}'", 'error')
		else
			TransactionError.new("#{row['ACTIVITY_ID']}: AccountTransfer not found", 'error')
		end
	end
end