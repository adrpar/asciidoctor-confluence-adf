require 'fastimage'
require 'pp'

# Module for handling image conversion and dimension detection
module ImageHandler
  # Helper method to detect and calculate image dimensions
  def detect_image_dimensions(node, width = nil, height = nil, is_inline = false)
    width = width || node.attr('width')&.to_i
    height = height || node.attr('height')&.to_i
    target = is_inline ? node.target : node.attr('target')
    
    return [width, height] if width && height

    begin
      doc = node.document
      
      # For debugging purposes
      warn "DEBUG: Image URI='#{node.normalize_system_path target}'"
      unless is_inline
        # Log the attributes that affect image resolution for debugging
        imagesdir = doc.attr('imagesdir')
        base_dir = doc.base_dir
        doc_file = doc.respond_to?(:docfile) ? doc.docfile : nil
        warn "DEBUG: Image target='#{target}', base_dir='#{base_dir}', docfile='#{doc_file}', imagesdir='#{imagesdir}'"
      end
      
      # Branch based on whether it's a remote URL
      if target.start_with?('http://', 'https://')
        width, height = detect_remote_image_dimensions(target, width, height, is_inline)
      else
        # For local files, try various resolution strategies
        width, height = detect_local_image_dimensions(target, doc, width, height, is_inline)
      end
    # rescue => e
    #   # Catch any errors that might occur during image resolution
    #   type = is_inline ? "inline image" : "image"
    #   warn "Error determining #{type} dimensions for '#{target}': #{e.message}" unless is_inline
    end

    [width, height]
  end
  
  def detect_local_image_dimensions(target, document, width = nil, height = nil, is_inline = false)
    images_dir_attr = document.attr('imagesdir')

    # Log attributes for debugging
    unless is_inline
      warn "DEBUG: Resolving local image: target='#{target}', base_dir='#{document.base_dir}', imagesdir='#{images_dir_attr || ''}'"
    end

    # Create a list of potential paths to search for the image using Asciidoctor's path resolver.
    search_paths = []

    # Path 1: Relative to the imagesdir attribute. This is the highest priority.
    # We construct the relative path first, then ask Asciidoctor to normalize it against the base_dir.
    if images_dir_attr && !images_dir_attr.empty?
      search_paths << document.normalize_system_path(File.join(images_dir_attr, target))
    end

    # Path 2: Relative to the document's base directory (fallback).
    search_paths << document.normalize_system_path(target)

    # Remove duplicates and find the first path that actually exists.
    found_path = search_paths.compact.uniq.find { |path| File.exist?(path) }

    if found_path
      unless is_inline
        warn "SUCCESS: Found local image at: #{found_path}"
      end
      dimensions = FastImage.size(found_path)
      if dimensions
        original_width, original_height = dimensions
        width, height = calculate_dimensions(width, height, original_width, original_height)
      end
    else
      unless is_inline
        warn "FAILURE: Could not find local image '#{target}'. Tried the following locations:"
        search_paths.uniq.each { |path| warn "  - #{path}" }
      end
    end
    
    [width, height]
  end
  
  # Helper method to detect dimensions from a remote image URI
  def detect_remote_image_dimensions(image_location, width = nil, height = nil, is_inline = false)
    begin
      dimensions = FastImage.size(image_location)
      if dimensions
        original_width = dimensions[0]
        original_height = dimensions[1]
        
        width, height = calculate_dimensions(width, height, original_width, original_height)
      end
    rescue => e
      error_msg = "Could not determine size for remote image: #{image_location}"
      error_msg += ". Reason: #{e.message}" unless is_inline
      warn error_msg unless is_inline
    end
    
    [width, height]
  end

  # Helper method to calculate dimensions while preserving aspect ratio
  def calculate_dimensions(width, height, original_width, original_height)
    if width && !height
      height = (width.to_f / original_width * original_height).to_i
    elsif height && !width
      width = (height.to_f / original_height * original_width).to_i
    else
      # If neither is specified, use the original dimensions
      width ||= original_width
      height ||= original_height
    end
    
    [width, height]
  end
  
  # Helper method to get the document directory from an Asciidoctor document
  def get_document_directory(document)
    if document.respond_to?(:docfile) && document.docfile
      # Get directory from document's file path
      return File.dirname(document.docfile)
    elsif document.respond_to?(:directory) && document.directory
      # Some documents directly expose their directory
      return document.directory
    else
      # Fall back to base_dir if no better option
      return document.base_dir
    end
  end
  
  # Convert a regular image node to ADF format
  def convert_image(node)
    # Get dimensions (either from attributes or detected from file)
    width, height = detect_image_dimensions(node)

    # Build the node with the dimensions
    self.node_list << {
      "type" => "mediaSingle",
      "attrs" => { "layout" => "center" },
      "content" => [
        {
          "type" => "media",
          "attrs" => {
            "type" => "file",
            "id" => node.attr('target'),
            "collection" => "attachments",
            "alt" => node.attr('alt') || "",
            "occurrenceKey" => node.attr('occurrenceKey') || SecureRandom.uuid,
            "width" => width,
            "height" => height
          }.compact
        }
      ]
    }
  end

  # Convert an inline image node to ADF format
  def convert_inline_image(node)
    # Get dimensions (either from attributes or detected from file)
    width, height = detect_image_dimensions(node, nil, nil, true)

    # Build the node with the dimensions (possibly determined from the file)
    {
      "type" => "mediaInline",
      "attrs" => {
        "type" => "file",
        "id" => node.target || "unknown-id",
        "collection" => "attachments",
        "alt" => node.attr('alt') || "",
        "occurrenceKey" => node.attr('occurrenceKey') || SecureRandom.uuid,
        "width" => width,
        "height" => height,
        "data" => node.attr('data') || {}
      }.compact
    }.to_json
  end
end
