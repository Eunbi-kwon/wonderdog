require_relative("index_and_type")

module Wukong
  module Elasticsearch

    # This module overrides some methods defined in
    # Wukong::Hadoop::HadoopInvocation.  The overrides will only come
    # into play if the job's input or output paths are URIs beginning
    # with 'es://', implying reading or writing to/from Elasticsearch
    # indices.
    module HadoopInvocationOverride

      # The input format when reading from Elasticsearch as defined in
      # the Java code accompanying Wonderdog.
      #
      # @param [String]
      STREAMING_INPUT_FORMAT  = "com.infochimps.elasticsearch.ElasticSearchStreamingInputFormat"

      # The output format when writing to Elasticsearch as defined in
      # the Java code accompanying Wonderdog.
      #
      # @param [String]
      STREAMING_OUTPUT_FORMAT = "com.infochimps.elasticsearch.ElasticSearchStreamingOutputFormat"

      # A regular expression that matches URIs describing an
      # Elasticsearch index and/or type to read/write from/to.
      #
      # @param [Regexp]
      ES_SCHEME_REGEXP        = %r{^es://}

      # Does this job read from Elasticsearch?
      #
      # @return [true, false]
      def reads_from_elasticsearch?
        settings[:input] && settings[:input] =~ ES_SCHEME_REGEXP
      end

      # The input format to use for this job.
      #
      # Will override the default value to STREAMING_INPUT_FORMAT if
      # reading from Elasticsearch.
      #
      # @return [String]
      def input_format
        reads_from_elasticsearch? ? STREAMING_INPUT_FORMAT : super()
      end

      # The input index to use.
      #
      # @return [IndexAndType]
      def input_index
        @input_index ||= IndexAndType.new(settings[:input])
      end

      # The input paths to use for this job.
      #
      # Will override the default value with a temporary HDFS path
      # when reading from Elasticsearch.
      #
      # @return [String]
      def input_paths
        if reads_from_elasticsearch?
          elasticsearch_hdfs_tmp_dir(input_index)
        else
          super()
        end
      end

      # Does this write to Elasticsearch?
      #
      # @return [true, false]
      def writes_to_elasticsearch?
        settings[:output] && settings[:output] =~ ES_SCHEME_REGEXP
      end

      # The output format to use for this job.
      #
      # Will override the default value to STREAMING_OUTPUT_FORMAT if
      # writing to Elasticsearch.
      #
      # @return [String]
      def output_format
        writes_to_elasticsearch? ? STREAMING_OUTPUT_FORMAT : super()
      end

      # The output index to use.
      #
      # @return [IndexAndType]
      def output_index
        @output_index ||= IndexAndType.new(settings[:output])
      end

      # The output path to use for this job.
      #
      # Will override the default value with a temporary HDFS path
      # when writing to Elasticsearch.
      #
      # @return [String]
      def output_path
        if writes_to_elasticsearch?
          elasticsearch_hdfs_tmp_dir(output_index)
        else
          super()
        end
      end

      # Adds Java options required to interact with the input/output
      # formats defined by the Java code accompanying Wonderdog.
      #
      # Will not change the default Hadoop jobconf options unless it
      # has to.
      #
      # @return [Array<String>]
      def hadoop_jobconf_options
        super() + [].tap do |o|
          o << java_opt('es.config', settings[:config]) if reads_from_elasticsearch? || writes_to_elasticsearch?
          
          if reads_from_elasticsearch??
            o << java_opt('elasticsearch.input.index',          input_index.index)
            o << java_opt('elasticsearch.input.type',           input_index.type)
            o << java_opt('elasticsearch.input.splits',         settings[:input_splits])
            o << java_opt('elasticsearch.input.query',          settings[:query])
            o << java_opt('elasticsearch.input.request_size',   settings[:request_size])
            o << java_opt('elasticsearch.input.scroll_timeout', settings[:scroll_timeout])
          end

          if writes_to_elasticsearch??
            o << java_opt('elasticsearch.output.index',       output_index.index)
            o << java_opt('elasticsearch.output.type',        output_index.type)
            o << java_opt('elasticsearch.output.index.field', settings[:index_field])
            o << java_opt('elasticsearch.output.type.field',  settings[:type_field])
            o << java_opt('elasticsearch.output.id.field',    settings[:id_field])
            o << java_opt('elasticsearch.output.bulk_size',   settings[:bulk_size])
          end
        end.flatten.compact
      end

      # Returns a temporary path on the HDFS in which to store log
      # data while the Hadoop job runs.
      #
      # @param [IndexAndType] io
      # @return [String]
      def elasticsearch_hdfs_tmp_dir io
        cleaner  = %r{[^\w/\.\-\+]+}
        io_part  = [io.index, io.type].compact.map { |s| s.gsub(cleaner, '') }.join('/')
        File.join(settings[:tmp_dir], io_part, job_name, Time.now.strftime("%Y-%m-%d-%H-%M-%S"))
      end
      
    end
  end
  
  if defined?(Hadoop::HadoopInvocation)
    Hadoop::HadoopInvocation.send(:include, Elasticsearch::HadoopInvocationOverride)
  end
end