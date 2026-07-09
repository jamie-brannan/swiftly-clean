class SwiftlyClean < Formula
  desc "Deep-cleans Xcode and SwiftPM build state"
  homepage "https://github.com/jamie-brannan/swiftly-clean"
  url "https://github.com/jamie-brannan/swiftly-clean/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "a566745eacb4f10976e9b1ad8b7ceba41d8f110c7e2e74fadf4a1ad721508116"
  license "MIT"

  def install
    bin.install "swiftly-clean.sh" => "swiftly-clean"
  end

  test do
    output = shell_output("#{bin}/swiftly-clean --help 2>&1", 1)
    assert_match "Unknown option", output
  end
end
