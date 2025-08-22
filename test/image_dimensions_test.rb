#!/usr/bin/env ruby

require 'minitest/autorun'
require 'asciidoctor'
require_relative '../src/adf_converter'

class ImageDimensionsTest < Minitest::Test
  def setup
    # Get the absolute path to the test image
    @test_image_path = File.expand_path("./fixtures/images/test.png", __dir__)
    
    # A public image URL for testing remote image paths
    # This is GitHub's logo with dimensions 512x512
    @test_image_url = "https://github.com/fluidicon.png"
  end

  def test_image_with_explicit_dimensions
    # Test when image dimensions are specified in the document
    input = "image::#{@test_image_path}[width=300,height=200]"
    doc = Asciidoctor.load(input, safe: :safe)
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify the dimensions are as specified in the document
    assert_equal 300, adf["content"][0]["attrs"]["width"]
    assert_equal 200, adf["content"][0]["attrs"]["height"]
  end

  def test_image_with_auto_detected_dimensions
    # Test when image dimensions are not specified and auto-detected
    input = "image::#{@test_image_path}[]"
    doc = Asciidoctor.load(input, safe: :safe)
    
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify the dimensions are auto-detected (should be 400x300 from our test image)
    assert_equal 400, adf["content"][0]["attrs"]["width"]
    assert_equal 300, adf["content"][0]["attrs"]["height"]
  end

  def test_image_with_explicit_width_auto_detect_height
    # Test when only width is specified, height is auto-detected to maintain aspect ratio
    input = "image::#{@test_image_path}[width=200]"
    doc = Asciidoctor.load(input, safe: :safe)
    
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify the width is as specified and height is auto-detected (should maintain aspect ratio)
    assert_equal 200, adf["content"][0]["attrs"]["width"]
    assert_equal 150, adf["content"][0]["attrs"]["height"]  # 300 * (200/400) = 150
  end

  def test_image_with_explicit_height_auto_detect_width
    # Test when only height is specified, width is auto-detected to maintain aspect ratio
    input = "image::#{@test_image_path}[height=150]"
    doc = Asciidoctor.load(input, safe: :safe)
    
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify the height is as specified and width is auto-detected (should maintain aspect ratio)
    assert_equal 200, adf["content"][0]["attrs"]["width"]  # 400 * (150/300) = 200
    assert_equal 150, adf["content"][0]["attrs"]["height"]
  end
  
  def test_remote_image_with_auto_detected_dimensions
    # Test when an image is specified via a remote URL
    input = "image::#{@test_image_url}[]"
    doc = Asciidoctor.load(input, safe: :safe)
    
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify the dimensions are auto-detected from the remote image
    # GitHub's fluidicon.png is 512x512
    assert_equal 512, adf["content"][0]["attrs"]["width"]
    assert_equal 512, adf["content"][0]["attrs"]["height"]
  end
  
  def test_remote_image_with_explicit_width_auto_detect_height
    # Test when a remote image has explicit width but auto-detected height
    input = "image::#{@test_image_url}[width=64]"
    doc = Asciidoctor.load(input, safe: :safe)
    
    converter = AdfConverter.new('adf')
    
    # Get the first block (the image)
    image_block = doc.blocks[0]
    # Convert the image
    converter.convert(image_block)
    
    # Get the ADF node
    adf = converter.node_list[0]
    
    # Verify width is as specified and height is calculated to maintain aspect ratio
    assert_equal 64, adf["content"][0]["attrs"]["width"]
    assert_equal 64, adf["content"][0]["attrs"]["height"] # 512 * (64/512) = 64
  end
end
