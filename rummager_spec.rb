require 'rummager'

describe Rummager::ClickImage, "#images" do
  it "returns !nil" do
    expect( Rummager::ClickImage.new 'foo' ).to_not be_nil
  end
end