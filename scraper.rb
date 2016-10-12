#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'uri'

require 'pry'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

terms = { 
  1 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_1st_Malayan_Parliament',
  2 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_2nd_Malaysian_Parliament',
  3 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_3rd_Malaysian_Parliament',
  4 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_4th_Malaysian_Parliament',
  5 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_5th_Malaysian_Parliament',
  6 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_6th_Malaysian_Parliament',
  7 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_7th_Malaysian_Parliament',
  8 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_8th_Malaysian_Parliament',
  9 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_9th_Malaysian_Parliament',
  10 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_10th_Malaysian_Parliament',
  11 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_11th_Malaysian_Parliament',
  12 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_12th_Malaysian_Parliament',
  13 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_13th_Malaysian_Parliament',
}

def noko_for(url)
  Nokogiri::HTML(open(url).read) 
end

@WIKI = 'http://en.wikipedia.org'
def wikilink(a)
  return if a.attr('class') == 'new' 
  URI.join(@WIKI, a['href']).to_s
end

def wikiname(a)
  return if a.attr('class') == 'new' 
  a.attr('title')
end

def party_and_coalition(td)
  unknown = { id: "unknown", name: "unknown" }
  return [unknown, unknown] unless td
  expand = ->(a) { { id: a.text, name: a.xpath('@title').text.split('(').first.strip } }
  return [expand.(td.css('a')), nil] if td.css('a').count == 1 
  return td.css('a').reverse.map { |a| expand.(a) }
end

def scrape_term(term, url)
  noko = noko_for(url)
  added = 0
  noko.xpath('//table[.//th[.="Member"]]//tr[td[2]]').each do |row|
    tds = row.css('td')
    sect = row.xpath('.//preceding::h2[1]').css('span.mw-headline').text.strip
    break if sect.include? 'Public Accounts Committee'

    member = tds[2].at_xpath('a') rescue nil
    next unless member
    (party, coalition) = party_and_coalition(tds[3])
    data = { 
      id: member.attr('title').downcase.gsub(/ /,'_').gsub('_(page_does_not_exist)',''),
      name: member.text.strip,
      state: row.xpath('.//preceding::h3[1]').css('span.mw-headline').text.strip,
      constituency: tds[1].text.strip,
      constituency_id: '%s-%s' % [ tds[0].text.strip, term ],
      wikipedia: wikilink(member),
      wikipedia__en: wikiname(member),
      party_id: party[:id],
      party: party[:name],
      term: term,
      source: url,
    }
    data[:area] = [data[:constituency], data[:state]].reject(&:empty?).compact.join(", ")
    data[:party_id] = 'PKR' if data[:party_id] == 'KeADILan'
    data[:coalition] = coalition[:name] if coalition
    data[:coalition_id] = coalition[:id] if coalition
    added += 1
    ScraperWiki.save_sqlite([:id, :constituency, :term], data) 
  end
  return added
end

# Start with a clean slate…
ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
terms.each do |term, url|
  added = scrape_term(term, url)
  puts "Term #{term}: #{added}"
end

