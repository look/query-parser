require 'elasticsearch'

module ElasticsearchHelpers
  def self.client
    @client ||= Elasticsearch::Client.new(:log => true)
  end

  def self.search(query_dsl)
    client.search(:index => 'query_parser_test', :type => 'books', :body => query_dsl)
  end

  def self.create_index!
    if client.indices.exists?(:index => 'query_parser_test')
      client.indices.delete(:index => 'query_parser_test')
    end

    client.indices.create(:index => 'query_parser_test',
                          :body => {
                            :settings => {
                              :index => {
                                :mapper => {
                                  :dynamic => false
                                }
                              }
                            },
                            :mappings => {
                              :books => {
                                :_all => { :enabled => false },
                                :properties => {
                                  :title => {
                                    :type => 'text',
                                    :analyzer => 'standard'
                                  },
                                  :author => {
                                    :type => 'text',
                                    :analyzer => 'standard'
                                  },
                                  :publication_year => {
                                    :type => 'integer'
                                  }
                                }
                              }
                            }
                          })
  end

  def self.prepare_corpus!
    create_index!
    index_documents
    wait_for_indexing
  end

  # It takes a moment for documents to become available for search
  def self.wait_for_indexing
    retries = 0
    loop do
      results = search(:query => {:match_all => {}})

      if results['hits']['hits'].size == corpus.size
        break
      end

      if retries > 5
        raise "Error indexing corpus. Got these results: #{results}"
      end

      retries += 1
      sleep(0.5)
    end
  end

  def self.corpus
    [
      {:title => "The Cat in the Hat", :author => ["Theodor Geisel", "Doctor Seuss"], :publication_year => 1957},
      {:title => "Cat Sense", :author => "John Bradshaw", :publication_year => 2013},
      {:title => "How to Tell If Your Cat Is Plotting to Kill You", :author => "Matthew Inman", :publication_year => 2012}
    ]
  end

  def self.index_documents
    corpus.each_with_index do |doc, index|
      client.index(:index => 'query_parser_test',
                   :type => 'books',
                   :id => index,
                   :body => doc)

    end
  end
end
