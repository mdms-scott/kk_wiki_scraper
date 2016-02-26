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
      Capybara::Poltergeist::Driver.new(app,
        :phantomjs_logger => suppressor,
        :timeout => 180,
        :js_errors => false,
        :phantomjs_options => [
          '--load-images=no',
          '--ignore-ssl-errors=yes'
        ]
      )
    end
    Capybara.default_driver = :poltergeist
  end

  def build_index retry_id=0
    visit INDEX_URL

    kanmusu = []
    tables = all("TABLE.wikitable.typography-xl-optout")

    tables.each do |table|
      table.all("TR").drop(retry_id).each_with_index do |tr, i|
        tds = tr.all("TD")
        unless tds.empty? || tds[0].text.nil? || tds[0].text == ''
          id = tds[0].text
          name = tds[1].find("A").text
          url = tds[1].find("A")[:href]
          kanmusu << {id: id, name: name, url: url, index: i}
        end
      end
    end

    kanmusu.each do |waifu|
      scrape_lines(waifu[:id], waifu[:name], waifu[:url], waifu[:index])
    end

  end

  def scrape_lines id, name, url, index
    begin
      print "Extracting #{id} - #{name} - URL: #{url}..."

      @hash = {id => {:name => name, :dialogue => {}, :hourly => {}}}

      visit url

      tables = all("TABLE.wikitable.typography-xl-optout")

      if page.has_selector?("SPAN#Kai.mw-headline") && ship_tier?(name) == :base
        tables = tables.to_a
        tables.delete_at(1)
      end

      tables.each do |table|
        scrape_dialogue_table(table, id)
      end

      File.open("output/#{id}.json", "w") do |f|
        f.write(JSON.pretty_generate(@hash))
      end

      print " Done!"
      puts ''
    rescue Capybara::Poltergeist::StatusFailError
      puts "TIMED OUT AND SHIT AUGH ON ID #{id} index #{index}"
      build_index(index)
    end
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

  def ship_tier? name
    if name.match(/Kai Ni/)
      return :kai_ni
    elsif name.match(/Kai/)
      return :kai
    elsif name.match(/Zwei/)
      return :zwei
    elsif name.match(/Drei/)
      return :drei
    else
      return :base
    end
  end

end

KkWikiScraper.new.build_index