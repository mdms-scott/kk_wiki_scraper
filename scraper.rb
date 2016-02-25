require 'json'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'

class KkWikiScraper
  include Capybara::DSL

  def initialize
    Capybara.default_driver = :poltergeist
  end

  def scrape_lines url
    visit url

    
    @ship_name = find("div.header-column.header-title").find("h1").text
    puts "ship name is: #{@ship_name}"
    
    tables = all("TABLE.wikitable.typography-xl-optout")

    tables.each do |table|
      scrape_dialogue_table(table)
    end
    
  end

  def scrape_dialogue_table table
    table.all("TR").each do |tr|
      tds = tr.all("TD")
      if !tds.empty?
        if tds.count == 1
          if tds.first.text.match(/is shared with/)
            matches = tds.first.text.split(/((.*) is shared with |, | and )/) - ['', ', ', ' and ']
            shared_id = matches[1]
            matches.drop(2).each do |match|
              puts "ID: #{parameterize_id(match)} -> #{parameterize_id(shared_id)}"
            end
          end
        else
          puts 'ID: ' + parameterize_id(tds.first.text)
          puts "TEXT: #{tds[2].text}"
        end
      end
    end
  end

  def parameterize_id id
    id.gsub(' Play', '').gsub(/[^\w\s]/, '').gsub(/\s+/, ' ').gsub(' ', '_').downcase
  end

end

KkWikiScraper.new.scrape_lines("http://kancolle.wikia.com/wiki/Yamato")