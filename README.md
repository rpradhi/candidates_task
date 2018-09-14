Code Optimization:

1. Configured the FTP params as a constant
2. As ActiveRecord initialization is specific to class moved it ti csv_exporter.rb instead of Rspec.
3. The import retry count was always equal to 1 in initial version, because break always interrupted 5.times loop on the first iteration;
So I am removing it completely in current version because this variable is always 1 and not saved or used anywhere except test checks
4. As I was using different ruby versions, included .ruby-version file to choose specific one
5. The code Logic had different Logic in single class file as below,
   a. Marba server Integration
   b. CSV reading
   c. Transaction & Validation
   d. Error Handling

   Changed the code which has Import Logic as seperate Module and updated the rspec wherever code tweeks has been done.
   Changed the code to have error handling string to sperate class as TransacitionError, where you define error messages. This leads to code maintainability
   Removed variables that duplicate class variables.

Further improvements:

1. I see this functionality to be renamed as CSVImporter as the data is imported from csv
2. Data validation can be seperated as we did for TransactionErrors
3. Transaction Building can be built as an object

Task
=====

The code presented in the task is running in a cronjob every 1 hour as the following task:

```ruby
namespace :mraba do
  task :import do
    CsvExporter.transfer_and_import
  end
end
```

It is connecting via FTP to the "Mraba" service and importing list of transactions from there. The code have the following issues:

* runs very slow
* when occasionally swallow errors
* tests for the code are unreliable and incomplete
* had for new team members to get around it
* not following coding standards

__Instalation__

```
bundle
```

__Test running__
```
rake
```
