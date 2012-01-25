#!/usr/bin/ruby
#
# md2epub.rb
#
# by David Briggs
#
# heavily based off Ben Crowder's md2epub.py
# http://bencrowder.net/
#
# Based off Matt Turner's GetBook.py
# http://staff.washington.edu/mdturner/personal.htm

require 'fileutils'
require 'redcarpet'
require 'zip/zip'

class Chapter
  attr_accessor :title, :filename, :htmlfile, :id, :children
	def initialize
  	@children = []
	end
end

class EPub
  attr_accessor :title, :author, :lang, :basename, :path, :bookid, :url, :css, :cover, :toc, :images, :children, :maxdepth
  def initialize
	  @lang = 'en-US'
	  @images = []				# list of images to be included
	  @children = []			# list of Chapters

	  @navpointcount = 1		# used for navpoint counts
	  @chapterids = []
	  @maxdepth = 1
  end

	# takes a list of chapters and writes the <item> tags for them and their children
	def write_items(children, f, pre)
	  children.each do |chapter|
			# For child chapters, prepend the parent id to make this one unique
			id = unique_id(chapter.id, pre)

			# Make sure we don't put duplicates in
			if @chapterids.include?(id)
			  STDERR.puts "Duplicate ID: #{id}"
				exit -1
			else
				@chapterids << id
			end

			# Write it out
			f.puts "\t\t<item id=\"#{id}\" href=\"#{chapter.htmlfile}\" media-type=\"application/xhtml+xml\" />"
			write_items(chapter.children, f, id) if chapter.children
		end
	end


	# takes a list of chapters and writes the <itemref> tags for them and their children
	def write_itemrefs(children, f, pre)
	  children.each do |chapter|
      id = unique_id(chapter.id, pre)
			f.puts "\t\t<itemref idref=\"#{id}\" />"
			write_itemrefs(chapter.children, f, id) if chapter.children
		end
	end


	# takes a list of chapters and writes them and their children to a navmap
	def write_chapter_navpoints(children, f, pre)
	  children.each do |chapter|
      id = unique_id(chapter.id, pre)

			f.puts "\t\t<navPoint id=\"navpoint-#{@navpointcount.to_s}\" playOrder=\"#{@navpointcount.to_s}\">"
			f.puts "\t\t\t<navLabel><text>#{chapter.title}</text></navLabel>"
			f.puts "\t\t\t<content src=\"#{chapter.htmlfile}\"/>"
			@navpointcount += 1
			write_chapter_navpoints(chapter.children, f, id) if chapter.children
			f.puts "\t\t</navPoint>"
		end
	end


	# takes a list of chapters and converts them and their children to Markdown
	def convert_chapters_to_markdown(children)
	  children.each do |chapter|
			begin
				input = File.open('../' + chapter.filename, 'r')
				f = File.open(chapter.htmlfile, 'w')
			rescue
				STDERR.puts "Error reading file '#{chapter.filename}' from table of contents."
				exit -1
			end
			sourcetext = input.read
			input.close

			# write HTML header
			f.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      f.puts "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
      f.puts "<html xmlns=\"http://www.w3.org/1999/xhtml\">"
      f.puts "<head>"
      f.puts "<title>#{@title}</title>"
			f.puts "<link rel=\"stylesheet\" type=\"text/css\" href=\"#{File.basename(@css)}\" />" if @css
			f.puts "</head>"
			f.puts "<body>"

			# write the Markdowned text
			htmltext = markdown(sourcetext)
			f.puts htmltext.gsub(/<hr>/, "<hr />")

			# write HTML footer
			f.puts "</body>"
			f.puts "</html>"

			f.close

			convert_chapters_to_markdown(chapter.children) if chapter.children
		end
	end


	# the main worker
	def save
		# get current working directory
		cwd = Dir.pwd
		
		# create directory for the ePub
		FileUtils.mkdir @path
		FileUtils.cd @path

		begin
			# make the META-INF/container.xml
			FileUtils.mkdir 'META-INF'
			FileUtils.cd 'META-INF' do
			  f = File.open('container.xml','w')
			  f.puts "<?xml version=\"1.0\"?>"
			  f.puts "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
			  f.puts "\t<rootfiles>"
			  f.puts "\t\t<rootfile full-path=\"content.opf\" media-type=\"application/oebps-package+xml\" />"
			  f.puts "\t</rootfiles>"
			  f.puts "</container>"
			  f.close
		  end

			# make åmetadata.opf
			f = File.open('content.opf','w')
			f.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
			f.puts "<package version=\"2.0\" xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"BookId\">"
			f.puts "\t<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:opf=\"http://www.idpf.org/2007/opf\">"
			f.puts "\t\t<dc:title>#{@title}</dc:title>"
			f.puts "\t\t<dc:creator opf:role=\"aut\">#{@author}</dc:creator>"
			f.puts "\t\t<dc:language>#{@lang}</dc:language>"
			f.puts "\t\t<dc:identifier id=\"BookId\">#{@url}</dc:identifier>"
			f.puts "\n\t\t<meta name=\"cover\" content=\"book-cover\" />" if @cover
			f.puts "\t</metadata>"
			f.puts "\t<manifest>"
			f.puts "\t\t<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\" />"
			f.puts "\t\t<item id=\"style\" href=\"#{File.basename(@css)}\" media-type=\"application/css\" />" if @css
      
			if @cover
				imagefile = File.basename(@cover)
				ext = File.extname(imagefile)[1..-1]	# get the extension
				ext = 'jpeg' if ext == 'jpg'
				f.puts "\t\t<item id=\"book-cover\" href=\"#{imagefile}\" media-type=\"image/#{ext}\" />"
			end

			# write the <item> tags
			write_items(@children, f, nil)
      
      @images.each do |image|
				imagefile = File.basename(image)
				ext = File.extname(imagefile)[1..-1]	# get the extension
				ext = 'jpeg' if ext == 'jpg'
				f.puts "\t\t<item id=\"#{imagefile}\" href=\"#{imagefile}\" media-type=\"image/#{ext}\" />"
      end
			f.puts "\t</manifest>"
			f.puts "\t<spine toc=\"ncx\">"

			# write the <itemref> tags
			write_itemrefs(@children, f, nil)

			f.puts "\t</spine>"

      if @toc
			  f.puts "\t<guide>"
			  f.puts "\t\t<reference type=\"toc\" title=\"Table of Contents\" href=\"#{@toc}.html\" />"
			  f.puts "\t</guide>"
			end

			f.puts "</package>"

			f.close

			# make toc.ncx
			f = File.open('toc.ncx','w')
			f.puts "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
			f.puts "<ncx version=\"2005-1\" xmlns=\"http://www.daisy.org/z3986/2005/ncx/\">"
			f.puts "\t<head>"
			f.puts "\t\t<meta name=\"dtb:uid\" content=\"#{@url}\" />"
			f.puts "\t\t<meta name=\"dtb:depth\" content=\"#{@maxdepth.to_s}\" />"
			f.puts "\t\t<meta name=\"dtb:totalPageCount\" content=\"0\" />"
			f.puts "\t\t<meta name=\"dtb:maxPageNumber\" content=\"0\" />"
			f.puts "\t</head>"
			f.puts "\t<docTitle>"
			f.puts "\t\t<text>#{@title}</text>"
			f.puts "\t</docTitle>"
			f.puts "\t<navMap>"

			write_chapter_navpoints(@children, f, nil)

			f.puts "\t</navMap>"
			f.puts "</ncx>"
			f.close

			# convert the texts to Markdown and save in the directory
			convert_chapters_to_markdown(@children)

			# if there's a CSS file, copy it in
			if @css
				if not File.exists? "../#{@css}"
					STDERR.puts "CSS file doesn't exist."
					exit -1
				end
				css = File.open("../#{@css}", 'r')
				csstext = css.read
				css.close
				File.open(File.basename(@css), 'w') do |f|
				  f.write(csstext)
			  end
			end

			# copy cover art into the directory
			if @cover
				if not File.exists? "../#{@cover}"
					STDERR.puts "Cover art file doesn't exist."
					exit -1
				end
				dest = File.basename(@cover)
				FileUtils.cp "../#{@cover}", dest
			end

			# copy images into the directory
			@images.each do |image|
			  dest = File.basename(image)
				FileUtils.cp "../#{image}", dest
			end

      # now zip the ePub up
      FileUtils.cd cwd
      output_path = File.expand_path("#{@basename}.epub")
      Zip::ZipOutputStream::open(output_path) do |os|
        os.put_next_entry("mimetype", nil, nil, Zip::ZipEntry::STORED, Zlib::NO_COMPRESSION)
        os <<  "application/epub+zip"
      end
      FileUtils.cd @path
      zipfile = Zip::ZipFile.open(output_path)
      zipfile.add('META-INF/container.xml', 'META-INF/container.xml')
      Dir.glob("*").each do |path|
        zipfile.add(path, path)
      end
      zipfile.commit
      
      FileUtils.cd cwd
      FileUtils.rm_rf(@path)
		rescue
			puts "Unexpected error: "

			# if something went wrong, remove the temp directory
			FileUtils.cd cwd
			FileUtils.rm_rf(@path)
		end
	end
	
	def add_chapter(chapter)
  	@children << chapter
  end

private

	def unique_id(id, pre)
	  if pre
			"#{pre}_#{id}"
		else
			"#{id}"
		end
	end
	
	def markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
            :autolink => true, :space_after_headers => true)
    return markdown.render(text)
  end
		
end


def process_book(filename)
	epub = EPub.new

	now = Time.now
	epub.basename = filename.split('.')[0]
	epub.path = "#{epub.basename}_#{now.year}-#{now.month}-#{now.day}_#{now.hour}-#{now.min}-#{now.sec}"
	epub.url = "http://localhost/#{epub.path}"		# dummy URL, replaced in control file

	File.open(filename, 'r') do |file|
	  while line = file.gets
		  next if line[0] == '#' or line.strip.empty?	# ignore comments and blank lines
		  if line.include?(':') and not line.include?('|')			# keywords
  			values = line.split(':')
  			keyword = values[0].strip
  			value = values[1].strip
  			case keyword
  		  when 'Title' then epub.title = value
  	    when 'Author' then epub.author = value
        when 'Language' then epub.lang = value
        when 'URL' then epub.url = value
        when 'TOC' then epub.toc = value
        when 'Image'
          images = value.split(',')
    			images.each { |image| epub.images << image.strip }
    		when 'Images'
          images = value.split(',')
  				images.each { |image| epub.images << image.strip }
  			when 'CSS' then epub.css = value
  		  when 'Cover' then epub.cover = value
  	    end
  		elsif line.include?('|')				# contents
  			values = line.split('|')
  			title = values[0].strip
  			filename = values[1].strip

  			chapter = Chapter.new
  			chapter.title = title
  			chapter.filename = filename

  			# replace extension with .html
  			basename = File.basename(chapter.filename)
  			chapter.htmlfile = "#{basename.split('.')[0..-2].join('.')}.html"

  			# for the ID, lowercase it all, strip punctuation, and replace spaces with underscores
  			chapter.id = chapter.title.downcase.gsub(' ', '_')
			
  			# if there's no ID left (because the chapter title is all Unicode, for example),
  			# use the basename of the file instead
  			chapter.id = basename.split('.')[0] if chapter.id.nil?

  			# add the current chapter
  			epub.add_chapter(chapter)
  		else
  			STDERR.puts "Error on the following line:\n"
  			STDERR.puts line
  		  exit -1
      end
    end
	end

	# create a (hopefully unique) book ID
	epub.bookid = "[#{epub.title}|#{epub.author}]"

	epub
end


##### Main

if ARGV.length > 0
  epub = process_book ARGV.shift
	epub.save
end