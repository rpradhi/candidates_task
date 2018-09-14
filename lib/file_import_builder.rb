module FileImportBuilder
  def import_from_local_files(files, send_email)
    files.each do |entry|
      result = import(local_path(entry))

      if result == 'Success'
        File.delete(local_path(entry))
        send_success_feedback(entry) if send_email
      else
        error_content = TransactionError.file_import_error(entry, result).message
        upload_error_file(entry, error_content)
        send_error_feedback(error_content) if send_email
        break
      end
    end
  end

  def local_path(filename)
    "#{Rails.root}/private/data/download/#{filename}"
  end

  def remote_path(filename)
    "/data/files/csv/#{filename}"
  end

  def send_success_feedback(filename)
    BackendMailer.send_import_feedback(
      'Successful Import',
      "Import of the file #{filename} done."
    )
  end

  def send_error_feedback(error_content)
    BackendMailer.send_import_feedback(
      'Import CSV failed',
      error_content
    )
  end

  def import(file, validation_only = false)
    begin
      result = import_file(file, validation_only)
    rescue StandardError => e
      result = { errors: [e.to_s], success: ['data lost'] }
    end

    result =
      if result[:errors].blank?
        'Success'
      else
        "Imported: #{result[:success].join(', ')} Errors: #{result[:errors].join('; ')}"
      end

    Rails.logger.info "CsvExporter#import time: \
                       #{Time.now.to_formatted_s(:db)} Imported #{file}: #{result}"

    result
  end

  def import_file(file, validation_only = false)
    @errors = []
    @dtaus = Mraba::Transaction.define_dtaus('RS', 8_888_888_888, 99_999_999, 'Credit collection')
    success_rows = []
    import_rows = CSV.read(
      file,
      col_sep: ';',
      headers: true,
      skip_blanks: true
    ).map do |r|
      [r.to_hash['ACTIVITY_ID'], r.to_hash]
    end
    import_rows.each do |index, row|
      next if index.blank?
      break unless validate_import_row(row)

      import_file_row_with_error_handling(row, validation_only, @dtaus)
      break unless @errors.empty?

      success_rows << row['ACTIVITY_ID']
    end
    add_datei if @errors.empty? && !validation_only && !@dtaus.is_empty?

    { success: success_rows, errors: @errors }
  end

  def add_datei
    source_path = "#{Rails.root}/private/upload"
    path_and_name = "#{source_path}/csv/tmp_mraba/DTAUS#{Time.now.strftime('%Y%m%d_%H%M%S')}"

    FileUtils.mkdir_p "#{source_path}/csv"
    FileUtils.mkdir_p "#{source_path}/csv/tmp_mraba"

    @dtaus.add_datei("#{path_and_name}_201_mraba.csv")
  end

  def import_file_row(row, validation_only, dtaus)
    case transaction_type(row)
    when 'AccountTransfer' then add_account_transfer(row, validation_only)
    when 'BankTransfer' then add_bank_transfer(row, validation_only)
    when 'Lastschrift' then add_dta_row(dtaus, row, validation_only)
    else @errors << TransactionError.transaction_type_error(row).message
    end
  end

  def import_file_row_with_error_handling(row, validation_only, dtaus)
    import_file_row(row, validation_only, dtaus)
  rescue StandardError => e
    @errors << TransactionError.exception_error(row, e).message
    # @errors << "#{row['ACTIVITY_ID']}: #{e}"
    false
  end

  def validate_import_row(row)
    errors = []
    unless %w[10 16].include? row['UMSATZ_KEY']
      @errors << TransactionError.validate_import_row(row).message
    end
    @errors += errors

    errors.empty?
  end

  def transaction_type(row)
    if row['SENDER_BLZ'] == '00000000' && row['RECEIVER_BLZ'] == '00000000'
      'AccountTransfer'
    elsif row['SENDER_BLZ'] == '00000000' && row['UMSATZ_KEY'] == '10'
      'BankTransfer'
    elsif row['RECEIVER_BLZ'] == '70022200' && ['16'].include?(row['UMSATZ_KEY'])
      'Lastschrift'
    else
      false
    end
  end

  def get_sender(row)
    sender = Account.find_by_account_no(row['SENDER_KONTO'])

    if sender.nil?
      @errors << TransactionError.get_sender_error(row).message
      # @errors << "#{row['ACTIVITY_ID']}: Account #{row['SENDER_KONTO']} not found"
    end

    sender
  end

  def add_account_transfer(row, validation_only)
    sender = get_sender(row)
    return @errors.last unless sender

    if row['DEPOT_ACTIVITY_ID'].blank?
      account_transfer = sender.credit_account_transfers.build(
        amount: row['AMOUNT'].to_f,
        subject: import_subject(row),
        receiver_multi: row['RECEIVER_KONTO']
      )
      account_transfer.date = row['ENTRY_DATE'].to_date
      account_transfer.skip_mobile_tan = true
    else
      account_transfer = sender.credit_account_transfers.find_by_id(row['DEPOT_ACTIVITY_ID'])
      if account_transfer.nil?
        @errors << TransactionError.account_transfer_error(row).message
        # @errors << "#{row['ACTIVITY_ID']}: AccountTransfer not found"
        return
      elsif account_transfer.state != 'pending'
        @errors << TransactionError.account_transfer_error(row, account_transfer.state).message
        # @errors << "#{row['ACTIVITY_ID']}: AccountTransfer state \
                    # expected 'pending' but was '#{account_transfer.state}'"
        return
      else
        account_transfer.subject = import_subject(row)
      end
    end
    if account_transfer && !account_transfer.valid?
      @errors << "#{row['ACTIVITY_ID']}: AccountTransfer validation error(s): \
                  #{account_transfer.errors.full_messages.join('; ')}"
    elsif !validation_only
      if row['DEPOT_ACTIVITY_ID'].blank?
        account_transfer.save!
      else
        account_transfer.complete_transfer!
      end
    end
  end

  def add_bank_transfer(row, validation_only)
    sender = get_sender(row)
    return @errors.last unless sender

    bank_transfer = sender.build_transfer(
      amount: row['AMOUNT'].to_f,
      subject: import_subject(row),
      rec_holder: row['RECEIVER_NAME'],
      rec_account_number: row['RECEIVER_KONTO'],
      rec_bank_code: row['RECEIVER_BLZ']
    )

    if !bank_transfer.valid?
      @errors << "#{row['ACTIVITY_ID']}: BankTransfer validation error(s): \
                  #{bank_transfer.errors.full_messages.join('; ')}"
    elsif !validation_only
      bank_transfer.save!
    end
  end

  def add_dta_row(dtaus, row, _validation_only)
    unless dtaus.valid_sender?(row['SENDER_KONTO'], row['SENDER_BLZ'])
      return @errors << "#{row['ACTIVITY_ID']}: BLZ/Konto not valid, csv fiile not written"
    end

    dtaus.add_buchung(
      row['SENDER_KONTO'],
      row['SENDER_BLZ'],
      convert_sender_name(row['SENDER_NAME']),
      BigDecimal(row['AMOUNT']).abs,
      import_subject(row)
    )
  end

  def convert_sender_name(sender_name)
    Iconv.iconv(
      'ascii//translit',
      'utf-8',
      sender_name
    ).to_s.gsub(/[^\w^\s]/, '')
  end

  def import_subject(row)
    subject = ''

    (1..14).each do |id|
      subject += row["DESC#{id}"].to_s unless row["DESC#{id}"].blank?
    end

    subject
  end
end
