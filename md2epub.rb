#!/usr/bin/env ruby
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
require 'digest/sha1'

class Chapter
  attr_accessor :subchapters
  attr_reader :title, :source, :id, :htmlfile
  def initialize(title, source)
    @title = title
    @source = source
    @id = Digest::SHA1.hexdigest "#{@title}_#{@source}"
    @htmlfile = "#{File.basename(@source).split('.')[0..-2].join('.')}.html"
    @subchapters = []
  end
  
  def add_subchapter(chapter)
    @subchapters << chapter
  end
  
  alias :<< :add_subchapter
end

class EPub
  def initialize(filename)
    @navpointcount = 1		# used for navpoint counts
    @chapterids = []
    @maxdepth = 1
    @chapters = []
	  
    now = Time.now

    @basename = File.basename(filename).split('.')[0]
    @path = "#{@basename}_#{now.year}-#{now.month}-#{now.day}_#{now.hour}-#{now.min}-#{now.sec}"

    config_file = File.expand_path(filename)
    if File.exists? config_file
      config_options = YAML.load_file(config_file)
    end
    if config_options[:chapters].nil?
      STDERR.puts "No chapters declared"
      exit 1
    end

    config_options[:chapters].each do |chapter|
      add_chapter(chapter)
    end

    @basename = config_options[:title].downcase.gsub(' ', '_')
    @working_dir = File.split(File.expand_path(filename))[0]
    @title = config_options[:title]
    @author = config_options[:author]
    @css = config_options[:css] || File.join(File.split(File.expand_path(__FILE__))[0],'epub.css')
    @cover = config_options[:cover]
    @lang = config_options[:lang] || 'en-US'
    
    # create a (hopefully unique) book ID
    @bookid = Digest::SHA1.hexdigest "[#{@title}|#{@author}]"
	  
  end
  
  def add_chapter(chapter_hash, parent_chapter = nil)
    chapter = Chapter.new(chapter_hash[:title], chapter_hash[:source])
    # add subchapters to the chapter if they are specified
    if chapter_hash[:subchapters]
      chapter_hash[:subchapters].each { |subchapter| add_chapter(subchapter, chapter) }
    end
    if parent_chapter
      # add subchapter to the parent chapter
      parent_chapter << chapter
    else
      # add chapter to the epub
      @chapters << chapter
    end
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
      convert_chapters_to_markdown(@chapters)

      # if there's a CSS file, copy it in
      if @css
        if not File.exists? @css
          STDERR.puts "CSS file doesn't exist."
          exit -1
        end
        css = File.open(@css, 'r')
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
  def self.chapter_items(chapters)
    result = []
    chapters.each do |chapter|
      result << "\t\t<item id=\"#{chapter.id}\" href=\"#{chapter.htmlfile}\" media-type=\"application/xhtml+xml\" />"
      result << self.chapter_items(chapter.subchapters) unless chapter.subchapters.empty?
    end
    result.join("\n")
  end

  # takes a list of chapters and writes the <itemref> tags for them and their children
  def self.itemrefs(chapters)
    result = []
    chapters.each do |chapter|
      result << "\t\t<itemref idref=\"#{chapter.id}\" />"
      result << self.itemrefs(chapter.subchapters) unless chapter.subchapters.empty?
    end
    result.join("\n")
  end

  # takes a list of chapters and writes them and their children to a navmap
  def chapter_navpoints(chapters)
    result = []
    chapters.each do |chapter|
      title = chapter.title.gsub('&', '&amp;')
      result << "\t\t<navPoint id=\"navpoint-#{@navpointcount}\" playOrder=\"#{@navpointcount}\">"
      result << "\t\t\t<navLabel><text>#{title}</text></navLabel>"
      result << "\t\t\t<content src=\"#{chapter.htmlfile}\"/>"
      @navpointcount += 1
      result << chapter_navpoints(chapter.subchapters) unless chapter.subchapters.empty?
      result << "\t\t</navPoint>"
    end
    result.join("\n")
  end

  # takes a list of chapters and converts them and their children to Markdown
  def convert_chapters_to_markdown(chapters)
    chapters.each do |chapter|
      sourcetext = ""
      begin
        File.open('../' + chapter.source, 'r') { |f| sourcetext = f.read }
      rescue
        STDERR.puts "Error reading file '#{chapter.source}' from table of contents."
        exit -1
      end

      File.open(chapter.htmlfile, 'w') do |f|
        # write HTML header
        f.puts header
        # write the Markdowned text
        f.puts markdown(sourcetext)
        # write HTML footer
        f.puts footer
      end
      convert_chapters_to_markdown(chapter.subchapters) unless chapter.subchapters.empty?
    end
  end
	
  def table_of_contents_xml
    toc = []
    toc << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    toc << "<ncx version=\"2005-1\" xmlns=\"http://www.daisy.org/z3986/2005/ncx/\">"
    toc << "\t<head>"
    toc << "\t\t<meta name=\"dtb:uid\" content=\"#{@bookid}\" />"
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
    toc << chapter_navpoints(@chapters)
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
    content << "\t\t<dc:identifier id=\"BookId\">#{@bookid}</dc:identifier>"
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
    content << EPub.chapter_items(@chapters)
    
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
    content << EPub.itemrefs(@chapters)
    content << "\t</spine>"

    if @toc
      content << "\t<guide>"
      content << "\t\t<reference type=\"toc\" title=\"Table of Contents\" href=\"#{@toc}\" />"
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
    toc << EPub.toc_line_items(@chapters)
    # write HTML footer
    toc << footer
    toc.join("\n")
  end
  
  def self.toc_line_items(chapters)
    line_items = ["<ul>"]
    chapters.each do |chapter|
      line_item = ["<li>"]
      title = chapter.title.gsub('&', '&amp;')
      line_item << "<a href=\"#{chapter.htmlfile}\">#{title}</a>"
      line_item << self.toc_line_items(chapter.subchapters) unless chapter.subchapters.empty?
      line_item << "</li>"
      line_items << line_item.join
    end
    line_items << "</ul>"
    line_items.join("\n")
  end
  
  def write_title_page
    title = []
    title << header
    title << "<h1 class=\"title\">#{@title}</h1>"
    title << "<h3 class=\"author\">By #{@author}</h3>"
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

if ARGV.length > 0
  epub = EPub.new(ARGV.shift)
  epub.save
end