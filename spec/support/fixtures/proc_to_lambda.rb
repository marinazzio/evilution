class ProcToLambdaTarget
  def kernel_proc
    proc { |a, b| [a, b] }
  end

  def kernel_proc_do
    proc do |value|
      value
    end
  end

  def proc_new
    Proc.new { |value| value }
  end

  def top_level_proc_new
    ::Proc.new { :ok }
  end

  def block_pass(block)
    proc(&block)
  end

  def already_lambda
    lambda { |value| value }
  end

  def other_receiver
    Handler.new { :ok }
  end
end
