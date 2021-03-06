#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require_rel 'lib/remove_notes'
require_rel 'lib/remove_party_counts'
require_rel 'lib/unspan_all_tables'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

terms = {
  1  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_1st_Malayan_Parliament',
  2  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_2nd_Malaysian_Parliament',
  3  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_3rd_Malaysian_Parliament',
  4  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_4th_Malaysian_Parliament',
  5  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_5th_Malaysian_Parliament',
  6  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_6th_Malaysian_Parliament',
  7  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_7th_Malaysian_Parliament',
  8  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_8th_Malaysian_Parliament',
  9  => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_9th_Malaysian_Parliament',
  10 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_10th_Malaysian_Parliament',
  11 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_11th_Malaysian_Parliament',
  12 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_12th_Malaysian_Parliament',
  13 => 'https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_13th_Malaysian_Parliament',
}

class MembershipRow < Scraped::HTML
  field :id do
    to_slugify = member ? member.attr('title') : tds[2].text.tidy
    binding.pry if to_slugify.downcase.include? 'party'
    to_slugify.downcase.tr(' ', '_').gsub('_(page_does_not_exist)', '')
  end

  field :name do
    member.text.tidy
  end

  field :state do
    noko.xpath('.//preceding::h3[1]').css('span.mw-headline').text.strip
  end

  field :constituency do
    tds[1].text.tidy
  end

  field :constituency_id do
    '%s-%s' % [tds[0].text.tidy, term]
  end

  field :wikidata do
    tds[2].css('a/@wikidata').text
  end

  field :wikipedia do
    href = tds[2].xpath('.//a[not(@class="new")]/@href') or return
    # TODO: make this absolute again. This version is just to make sure
    # we have minimal diffs
    href.text.sub('https', 'http')
  end

  field :wikipedia__en do
    href = tds[2].xpath('.//a[not(@class="new")]/@title') or return
    href.text
  end

  field :party_id do
    pid = party_and_coalition.first[:id]
    return 'PKR' if pid == 'KeADILan'
    pid
  end

  field :party do
    party_and_coalition.first[:name]
  end

  field :term do
    url.sub('https://en.wikipedia.org/wiki/Members_of_the_Dewan_Rakyat,_', '').to_i
  end

  field :source do
    url
  end

  field :area do
    [constituency, state].reject(&:empty?).compact.join(', ')
  end

  field :coalition do
    coalition_data[:name] if coalition_data
  end

  field :coalition_id do
    coalition_data[:id] if coalition_data
  end

  def vacant?
    tds[3].text.tidy == 'VAC'
  end

  private

  def tds
    @tds ||= noko.css('td')
  end

  def member
    @member ||= tds[2].at_xpath('a') || tds[2]
  end

  def coalition_data
    party_and_coalition.last
  end

  def party_and_coalition
    unknown = { id: 'unknown', name: 'unknown' }
    independent = { id: 'IND', name: 'Independent' }
    binding.pry unless td = tds[3]
    return [] if vacant?
    return [independent, independent] if tds[3].text.tidy == 'IND'
    # return [unknown, unknown] if td.css('a').count.zero?
    binding.pry if td.css('a').count.zero?
    expand = ->(a) { { id: a.text, name: a.xpath('@title').text.split('(').first.strip } }
    return [expand.call(td.css('a')), nil] if td.css('a').count == 1
    td.css('a').reverse.map { |a| expand.call(a) }
  end
end

class ListPage < Scraped::HTML
  decorator RemovePartyCounts
  decorator UnspanAllTables
  decorator RemoveNotes
  decorator Scraped::Response::Decorator::CleanUrls
  decorator WikidataIdsDecorator::Links

  field :members do
    members_table.xpath('.//tr[td[4]]').reject { |tr| tr.css('td').first.text == tr.css('td').last.text }.map do |row|
      fragment row => MembershipRow
    end
  end

  private

  def members_table
    noko.xpath('//table[.//th[contains(.,"Constituency")]]')
  end
end

data = terms.values.flat_map do |url|
  ListPage.new(response: Scraped::Request.new(url: url).response).members.reject(&:vacant?).map(&:to_h)
end
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id constituency term], data)
