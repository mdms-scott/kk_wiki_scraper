require 'json'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'poltergeist/suppressor'

class KkWikiScraper
  include Capybara::DSL

  INDEX_URL = "http://kancolle.wikia.com/wiki/Ship_list"

  def initialize
    suppressor = Capybara::Poltergeist::Suppressor.new(patterns: [/.*/])
    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, :phantomjs_logger => suppressor)
    end
    Capybara.default_driver = :poltergeist
  end

  def build_index
    visit INDEX_URL

    kanmusu = []
    tables = all("TABLE.wikitable.typography-xl-optout")

    tables.each do |table|
      table.all("TR").first(10).each do |tr|
        tds = tr.all("TD")
        unless tds.empty? || tds[0].text.nil? || tds[0].text == ''
          id = tds[0].text
          name = tds[1].find("A").text
          url = tds[1].find("A")[:href]
          kanmusu << {id: id, name: name, url: url}
        end
      end
    end

    kanmusu.each do |waifu|
      scrape_lines(waifu[:id], waifu[:name], waifu[:url])
    end

  end

  def scrape_lines id, name, url
    print "Extracting #{id} - #{name} - URL: #{url}..."

    @hash = {id => {:name => name, :dialogue => {}, :hourly => {}}}

    visit url

    tables = all("TABLE.wikitable.typography-xl-optout")

    tables.each do |table|
      scrape_dialogue_table(table, id)
    end

    File.open("output/#{id}.json", "w") do |f|
      f.write(JSON.pretty_generate(@hash))
    end

    print " Done!"
    puts ''
  end

  def scrape_dialogue_table table, id
    table_type = case table.all("TH").first.text
      when 'Event' then :dialogue
      when 'Time'  then :hourly
    end
    table.all("TR").each do |tr|
      tds = tr.all("TD")
      unless tds.empty?
        if tds.count == 1
          if tds.first.text.match(/is shared with/)
            matches = tds.first.text.split(/((.*) is shared with |, | and )/) - ['', ', ', ' and ']
            shared_id = matches[1]
            matches.drop(2).each do |match|
              @hash[id][table_type][parameterize_id(match).to_sym] = @hash[id][table_type][parameterize_id(shared_id).to_sym]
            end
          end
        else
          # key map to multiple and then select based on match /kai/kai ni/zwei/drei/etc
          @hash[id][table_type][parameterize_id(tds.first.text).to_sym] = tds[2].text
        end
      end
    end
  end

  def parameterize_id id
    id.gsub(' Play', '').gsub(/[^\w\s]/, '').gsub(/\s+/, ' ').gsub(' ', '_').downcase
  end

end

# KkWikiScraper.new.scrape_lines("http://kancolle.wikia.com/wiki/Yamato")
KkWikiScraper.new.build_index