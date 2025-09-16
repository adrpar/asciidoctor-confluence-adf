require 'fastimage'
require_relative 'adf_builder'
require_relative 'adf_logger'

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
      
      AdfLogger.debug "Image URI='#{node.normalize_system_path target}'"
      unless is_inline
        imagesdir = doc.attr('imagesdir')
        base_dir = doc.base_dir
        doc_file = doc.respond_to?(:docfile) ? doc.docfile : nil
        AdfLogger.debug "Image target='#{target}', base_dir='#{base_dir}', docfile='#{doc_file}', imagesdir='#{imagesdir}'"
      end
      
      # Branch based on whether it's a remote URL
      if target.start_with?('http://', 'https://')
        width, height = detect_remote_image_dimensions(target, width, height, is_inline)
      else
        # For local files, try various resolution strategies
        width, height = detect_local_image_dimensions(target, doc, width, height, is_inline)
      end
    rescue => e
      type = is_inline ? "inline image" : "image"
      AdfLogger.warn "Error determining #{type} dimensions for '#{target}': #{e.message}" unless is_inline
    end

    [width, height]
  end
  
  def detect_local_image_dimensions(target, document, width = nil, height = nil, is_inline = false)
    images_dir_attr = document.attr('imagesdir')

    unless is_inline
      AdfLogger.debug "Resolving local image: target='#{target}', base_dir='#{document.base_dir}', imagesdir='#{images_dir_attr || ''}'"
    end

    # Build candidate paths via helper
    search_paths = build_image_search_paths(document, target, images_dir_attr)
    found_path = search_paths.find { |path| File.exist?(path) }

    if found_path
      unless is_inline
        AdfLogger.info "SUCCESS: Found local image at: #{found_path}"
      end
      dimensions = FastImage.size(found_path)
      if dimensions
        original_width, original_height = dimensions
        width, height = calculate_dimensions(width, height, original_width, original_height)
      end
    else
      unless is_inline
        AdfLogger.warn "FAILURE: Could not find local image '#{target}'. Tried the following locations:"
        search_paths.uniq.each { |path| AdfLogger.warn "  - #{path}" }
      end
    end
    
    [width, height]
  end

  # Centralizes construction of candidate image search paths. Order matters.
  def build_image_search_paths(document, target, images_dir_attr)
    paths = []
    if images_dir_attr && !images_dir_attr.empty?
      paths << document.normalize_system_path(File.join(images_dir_attr, target))
    end
    paths << document.normalize_system_path(target)
    paths.compact.uniq
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
      AdfLogger.warn error_msg unless is_inline
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
    media = AdfBuilder.media(
      {
        'type' => 'file',
        'id' => node.attr('target'),
        'collection' => 'attachments',
        'alt' => node.attr('alt') || '',
        'occurrenceKey' => node.attr('occurrenceKey') || SecureRandom.uuid,
        'width' => width,
        'height' => height
      }.compact
    )
    self.node_list << AdfBuilder.media_single(layout: 'wide', width: width, width_type: 'pixel', media_node: media)
  end

  # Convert an inline image node to ADF format
  def convert_inline_image(node)
    width, height = detect_image_dimensions(node, nil, nil, true)
    media_inline = AdfBuilder.media_inline(
      {
        'type' => 'file',
        'id' => node.target || 'unknown-id',
        'collection' => 'attachments',
        'alt' => node.attr('alt') || '',
        'occurrenceKey' => node.attr('occurrenceKey') || SecureRandom.uuid,
        'width' => width,
        'height' => height,
        'data' => node.attr('data') || {}
      }.compact
    )
    register_inline_node(media_inline)
  end
end
