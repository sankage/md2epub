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
require 'yaml'

class EPub
  def initialize(filename)
	  @navpointcount = 1		# used for navpoint counts
	  @chapterids = []
	  @maxdepth = 1
	  
	  now = Time.now

  	@basename = File.basename(filename).split('.')[0]
  	@path = "#{@basename}_#{now.year}-#{now.month}-#{now.day}_#{now.hour}-#{now.min}-#{now.sec}"
  	@url = "http://localhost/#{@path}"		# dummy URL, replaced in control file

  	config_file = File.expand_path(filename)
  	if File.exists? config_file
  	  config_options = YAML.load_file(config_file)
    end
    if config_options[:chapters].nil?
      STDERR.puts "No chapters declared"
      exit 1
    end

    config_options[:chapters].each do |chapter|
      if chapter[:title].index(':')
        chapter[:id] = chapter[:title].split(':')[0].downcase.gsub(' ', '_')
      else
        chapter[:id] = chapter[:title][0..10]
      end
      chapter[:htmlfile] = "#{chapter[:source].split('.')[0..-2].join('.')}.html"
    end

    @basename = config_options[:title].downcase.gsub(' ', '_')
    @working_dir = File.split(File.expand_path(filename))[0]
    
    @title = config_options[:title]
    @author = config_options[:author]
    @css = config_options[:css]
    @cover = config_options[:cover]
    @lang = config_options[:lang] || 'en-US'
    @chapters = config_options[:chapters]

  	# create a (hopefully unique) book ID
  	@bookid = "[#{@title}|#{@author}]"
	  
  end
  
	# the main worker
	def save
		# get current working directory
		cwd = @working_dir
		FileUtils.cd cwd
		
		# create directory for the ePub
		FileUtils.mkdir @path
		FileUtils.cd @path

		begin
			# make the META-INF/container.xml
			FileUtils.mkdir 'META-INF'
			FileUtils.cd 'META-INF'
			File.open('container.xml','w') { |f| f.puts container_xml }
      FileUtils.cd '..'

      # make a table of contents file
      File.open('table_of_contents.html', 'w') { |f| f.puts write_toc }
      @toc = 'table_of_contents.html'
      
      # make a title page
      File.open('title_page.html', 'w') { |f| f.puts write_title_page }
      
			# make content.opf
			File.open('content.opf','w') { |f| f.puts content_xml }

			# make toc.ncx
			File.open('toc.ncx','w') { |f| f.puts table_of_contents_xml }

			# convert the texts to Markdown and save in the directory
			convert_chapters_to_markdown

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
			if @images
  			@images.each do |image|
  			  dest = File.basename(image)
  				FileUtils.cp "../#{image}", dest
  			end
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
			STDERR.puts "Error while saving epub."

			# if something went wrong, remove the temp directory
			FileUtils.cd cwd
			FileUtils.rm_rf(@path)
			exit 1
		end
	end

private
	
	def markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::XHTML,
            :autolink => true, :space_after_headers => true)
    return markdown.render(text)
  end
  
  # takes a list of chapters and writes the <item> tags for them and their children
	def chapter_items
	  result = []
	  @chapters.each do |chapter|
			# Make sure we don't put duplicates in
			if @chapterids.include?(chapter[:id])
			  STDERR.puts "Duplicate ID: #{chapter[:id]}"
				exit 1
			else
				@chapterids << chapter[:id]
			end

			result << "\t\t<item id=\"#{chapter[:id]}\" href=\"#{chapter[:htmlfile]}\" media-type=\"application/xhtml+xml\" />"
		end
		result.join("\n")
	end


	# takes a list of chapters and writes the <itemref> tags for them and their children
	def itemrefs
	  result = []
	  @chapters.each do |chapter|
			result << "\t\t<itemref idref=\"#{chapter[:id]}\" />"
		end
		result.join("\n")
	end


	# takes a list of chapters and writes them and their children to a navmap
	def chapter_navpoints
	  result = []
	  @chapters.each do |chapter|
			result << "\t\t<navPoint id=\"navpoint-#{@navpointcount.to_s}\" playOrder=\"#{@navpointcount.to_s}\">"
			result << "\t\t\t<navLabel><text>#{chapter[:title]}</text></navLabel>"
			result << "\t\t\t<content src=\"#{chapter[:htmlfile]}\"/>"
			result << "\t\t</navPoint>"
			@navpointcount += 1
		end
		result.join("\n")
	end


	# takes a list of chapters and converts them and their children to Markdown
	def convert_chapters_to_markdown
	  @chapters.each do |chapter|
			begin
				input = File.open('../' + chapter[:source], 'r')
				f = File.open(chapter[:htmlfile], 'w')
			rescue
				STDERR.puts "Error reading file '#{chapter[:source]}' from table of contents."
				exit -1
			end
			sourcetext = input.read
			input.close

			# write HTML header
			f.puts header
			# write the Markdowned text
			f.puts markdown(sourcetext)
			# write HTML footer
			f.puts footer

			f.close
		end
	end
	
	def table_of_contents_xml
	 	toc = []
		toc << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
		toc << "<ncx version=\"2005-1\" xmlns=\"http://www.daisy.org/z3986/2005/ncx/\">"
		toc << "\t<head>"
		toc << "\t\t<meta name=\"dtb:uid\" content=\"#{@url}\" />"
		toc << "\t\t<meta name=\"dtb:depth\" content=\"#{@maxdepth.to_s}\" />"
		toc << "\t\t<meta name=\"dtb:totalPageCount\" content=\"0\" />"
		toc << "\t\t<meta name=\"dtb:maxPageNumber\" content=\"0\" />"
		toc << "\t</head>"
		toc << "\t<docTitle>"
		toc << "\t\t<text>#{@title}</text>"
		toc << "\t</docTitle>"
		toc << "\t<navMap>"

		@navpointcount += 1
	  toc << "\t\t<navPoint id=\"navpoint-1\" playOrder=\"1\">"
		toc << "\t\t\t<navLabel><text>#{@title}</text></navLabel>"
		toc << "\t\t\t<content src=\"title_page.html\"/>"
		toc << "\t\t</navPoint>"

	  @navpointcount += 1
	  toc << "\t\t<navPoint id=\"navpoint-2\" playOrder=\"2\">"
		toc << "\t\t\t<navLabel><text>Table of Contents</text></navLabel>"
		toc << "\t\t\t<content src=\"#{@toc}\"/>"
		toc << "\t\t</navPoint>"
		
		toc << chapter_navpoints
		toc << "\t</navMap>"
		toc << "</ncx>"
		toc.join("\n")
	end

  def container_xml
    contain = []
	  contain << "<?xml version=\"1.0\"?>"
	  contain << "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">"
	  contain << "\t<rootfiles>"
	  contain << "\t\t<rootfile full-path=\"content.opf\" media-type=\"application/oebps-package+xml\" />"
	  contain << "\t</rootfiles>"
	  contain << "</container>"
	  contain.join("\n")
  end
  
  def content_xml
    content = []
		content << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
		content << "<package version=\"2.0\" xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"BookId\">"
		content << "\t<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:opf=\"http://www.idpf.org/2007/opf\">"
		content << "\t\t<dc:title>#{@title}</dc:title>"
		content << "\t\t<dc:creator opf:role=\"aut\">#{@author}</dc:creator>"
		content << "\t\t<dc:language>#{@lang}</dc:language>"
		content << "\t\t<dc:identifier id=\"BookId\">#{@url}</dc:identifier>"
		content << "\n\t\t<meta name=\"cover\" content=\"book-cover\" />" if @cover
		content << "\t</metadata>"
		content << "\t<manifest>"
		content << "\t\t<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\" />"
		content << "\t\t<item id=\"style\" href=\"#{File.basename(@css)}\" media-type=\"application/css\" />" if @css
    
		if @cover
			imagefile = File.basename(@cover)
			ext = File.extname(imagefile)[1..-1]	# get the extension
			ext = 'jpeg' if ext == 'jpg'
			content << "\t\t<item id=\"book-cover\" href=\"#{imagefile}\" media-type=\"image/#{ext}\" />"
		end
		
		# add title page
		content << "\t\t<item id=\"title_page\" href=\"title_page.html\" media-type=\"application/xhtml+xml\" />"
		
		# add table of contents
		content << "\t\t<item id=\"table_of_contents\" href=\"#{@toc}\" media-type=\"application/xhtml+xml\" />"

		# write the <item> tags
		content << chapter_items
    
    if @images
      @images.each do |image|
				imagefile = File.basename(image)
				ext = File.extname(imagefile)[1..-1]	# get the extension
				ext = 'jpeg' if ext == 'jpg'
				content << "\t\t<item id=\"#{imagefile}\" href=\"#{imagefile}\" media-type=\"image/#{ext}\" />"
      end
    end
		content << "\t</manifest>"
		content << "\t<spine toc=\"ncx\">"

    content << "\t\t<itemref idref=\"title_page\" />"
    content << "\t\t<itemref idref=\"table_of_contents\" />"
		# write the <itemref> tags
		content << itemrefs

		content << "\t</spine>"

    if @toc
		  content << "\t<guide>"
		  content << "\t\t<reference type=\"toc\" title=\"Table of Contents\" href=\"#{@toc}.html\" />"
		  content << "\t</guide>"
		end

		content << "</package>"
		content.join("\n")
  end
  
  def write_toc
    toc = []
    # write HTML header
		toc << header
    toc << "<h2>Table of Contents</h2>"
    toc << "<ul>"
    @chapters.each do |chapter|
      toc << "\t<li><a href=\"#{chapter[:htmlfile]}\">#{chapter[:title]}</a></li>"
    end
    toc << "</ul>"
		# write HTML footer
		toc << footer
		toc.join("\n")
  end
  
  def write_title_page
    title = []
    title << header
    
    title << "<h1 class=\"title\">#{@title}</h1>"
    title << "<div class=\"author\">By #{@author}</p>"
    
    title << footer
    title.join("\n")
  end
  
  def header
    # write HTML header
    head = []
		head << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    head << "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">"
    head << "<html xmlns=\"http://www.w3.org/1999/xhtml\">"
    head << "<head>"
    head << "<title>#{@title}</title>"
		head << "<link rel=\"stylesheet\" type=\"text/css\" href=\"#{File.basename(@css)}\" />" if @css
		head << "</head>"
		head << "<body>"
		head.join("\n")
  end
  
  def footer
    foot = []
    # write HTML footer
		foot << "</body>"
		foot << "</html>"
		foot.join("\n")
	end
		
end


##### Main

if ARGV.length > 0
  epub = EPub.new(ARGV.shift)
	epub.save
end