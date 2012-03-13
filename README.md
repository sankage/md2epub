md2epub.rb
==========

## DESCRIPTION

A command line ruby script to transform a collection of [markdown](http://daringfireball.net/projects/markdown/) files into an [epub](http://en.wikipedia.org/wiki/EPUB) file. It builds the epub using a [yaml](http://yaml.org/) formatted config file to describe the content.

## HOW TO USE

Create a yml file that includes the book's title, author, css file (optional), and chapters

```yaml
---
:title: Sample Story
:author: John Doe
:css: css/style.css
:chapters:
  - :title: "Chapter 1: The Adventure Begins"
    :source: chapter-01.md
  - :title: "Chapter 2: Once More Into the Demon's Den"
    :source: chapter-02.md
  - :title: "Chapter 3: The Lay of the Land"
    :source: chapter-03.md
```

Then just run the script with this file

```bash
./md2epub.rb sample.yml
```

If you wish for the results to be saved in another location, add the target folder to the command

```bash
./md2epub.rb sample.yml ~/Documents
```

If you have subchapters, add them to their parent chapter with the key :subchapters

```yaml
---
:title: Sample Story
:author: John Doe
:css: css/style.css
:chapters:
  - :title: "Chapter 1: The Adventure Begins"
    :source: chapter-01.md
  - :title: "Chapter 2: Once More Into the Demon's Den"
    :source: chapter-02.md
    :subchapters:
    - :title: "Section A: Really?"
      :source: chapter-02a.md
    - :title: "Section B: Man, I really liked that leg..."
      :source: chapter-02b.md
  - :title: "Chapter 3: The Lay of the Land"
    :source: chapter-03.md
```

## DEPENDENCIES

- redcarpet
- rubyzip
- yaml

## NOTES

This is largely based on the inner workings of Ben Crowder's [md2epub.py](https://github.com/bencrowder/md2epub).

This is my first attempt at taking a python script and re-writing it into ruby. So there are bound to be errors out the wazoo.