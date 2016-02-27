require 'json'
require 'capybara'
require 'capybara/dsl'
require 'capybara/poltergeist'
require 'poltergeist/suppressor'

class KkWikiScraper
  include Capybara::DSL

  INDEX_URL = "http://kancolle.wikia.com/wiki/Ship_list"

  def initialize
    # PhantomJS likes to output everything in console.log to STDOUT, and the wiki logs things... a lot
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

  # Build an index of all Kanmusu
  # Iterates over the index list on the wiki and will automatically pick up new Kanmusu
  def build_index retry_id=0
    visit INDEX_URL

    kanmusu = []
    tables = all("TABLE.wikitable.typography-xl-optout")

    # The Kanmusu are kept in two tables so iterate over both
    tables.each do |table|
      table.all("TR").each_with_index do |tr, i|
        tds = tr.all("TD")
        unless tds.empty? || tds[0].text.nil? || tds[0].text == ''
          id = tds[0].text
          name = tds[1].find("A").text
          url = tds[1].find("A")[:href]
          kanmusu << {id: id, name: name, url: url, index: i}
        end
      end
    end

    # haha
    kanmusu.each do |waifu|
      scrape_lines(waifu[:id], waifu[:name], waifu[:url], waifu[:index])
    end
  end

  # Acquire the tables filled with dialogue lines for a given Kanmusu
  def scrape_lines id, name, url, index
    begin
      print "Extracting #{id} - #{name} - URL: #{url}..."

      @hash = {id => {:name => name, :dialogue => {}, :hourly => {}}}

      visit url

      tables = all("TABLE.wikitable.typography-xl-optout")

      # If the Kanmusu has a table for Kai lines, but we are not looking at the Kai version, delete that table
      if page.has_selector?("SPAN#Kai.mw-headline") && ship_tier?(name) == :base
        tables = tables.to_a
        tables.delete_at(1)
      end

      tables.each do |table|
        scrape_dialogue_table(table, id, name)
      end

      File.open("output/#{id}.json", "w") do |f|
        f.write(JSON.pretty_generate(@hash))
      end

      print " Done!"
      puts ''
    rescue Capybara::Poltergeist::StatusFailError
      puts "TIMED OUT ON ID #{id} INDEX #{index}"
      build_index(index)
    end
  end

  # Acquire the dialogue lines from a given table
  def scrape_dialogue_table table, id, name
    table_type = case table.all("TH").first.text
      when 'Event' then :dialogue
      when 'Time'  then :hourly
    end
    table.all("TR").each do |tr|
      tds = tr.all("TD")
      unless tds.empty?
        if tds.count == 1
          # If a line is shared with others figure out what text is shared with which keys
          if tds.first.text.match(/is shared with/)
            matches = tds.first.text.split(/((.*) is shared with |, | and )/) - ['', ', ', ' and ']
            shared_id = matches[1]
            matches.drop(2).each do |match|
              @hash[id][table_type][parameterize_id(match).to_sym] = @hash[id][table_type][parameterize_id(shared_id).to_sym]
            end
          end
        else
          # If Kai/Kai Ni/etc lines are specified inline in the tables, figure out which one to use
          # There is not regular formatting on the wikia for this, as sometimes <p> tags are used,
          # sometimes they are not, and <br> are the only separations.
          @hash[id][table_type][parameterize_id(tds.first.text).to_sym] = tier_line(dialogue_line(tds[2]['innerText']), ship_tier?(name))
        end
      end
    end
  end

  # Convert an "id" into an underscored parameter name
  def parameterize_id id
    id.gsub(' Play', '').gsub(/[^\w\s]/, '').gsub(/\s+/, ' ').gsub(' ', '_').downcase
  end

  # Construct the hash of dialogue lines in the case of different "tiers" being specified inline in a TD
  def dialogue_line text
    result = {}
    lines = text.split(/\n/) - ['']
    # If there is only one line and it has a (kai) tag use it and remove the (kai) tag
    result[:base] = lines[0].nil? ? '' : lines[0].gsub(' (Kai)', '')
    lines.drop(1).each do |line|
      matches = line.match(/(.*)\((Kai|Kai Ni|Kai Ni A|Zwei|Drei)\)/)
      if matches.to_a.empty?
        result[:base] += (' ' + line)
      else
        result[matches[2].downcase.gsub(' ', '_').to_sym] = matches[1].strip
      end
    end

    result
  end

  # Determine the tier of the ship from the original index as it can't be determined from the shared page
  def ship_tier? name
    if name.match(/Kai Ni A/)
      return :kai_ni_a
    elsif name.match(/Kai Ni/)
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

  # Determine the line that should be used for a tier in descending order
  # Wow this is super ugly
  def tier_line text, tier
    if tier == :kai_ni_a
      if text[:kai_ni_a]
        return text[:kai_ni_a]
      elsif text[:kai_ni]
        return text[:kai_ni]
      elsif text[:kai]
        return text[:kai]
      else
        return text[:base]
      end
    elsif tier == :kai_ni
      if text[:kai_ni]
        return text[:kai_ni]
      elsif text[:kai]
        return text[:kai]
      else
        return text[:base]
      end
    elsif tier == :kai
      if text[:kai]
        return text[:kai]
      else
        return text[:base]
      end
    elsif tier == :zwei
      if text[:zwei]
        return text[:zwei]
      elsif text[:kai]
        return text[:kai]
      else
        return text[:base]
      end
    elsif tier == :drei
      if text[:drei]
        return text[:drei]
      elsif text[:zwei]
        return text[:zwei]
      elsif text[:kai]
        return text[:kai]
      else
        return text[:base]
      end
    else
      return text[:base]
    end
  end

end

# Run the script
KkWikiScraper.new.build_index
