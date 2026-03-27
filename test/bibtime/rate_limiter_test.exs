defmodule Bibtime.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Bibtime.RateLimiter

  setup do
    RateLimiter.reset()
    :ok
  end

  describe "check_rate/3" do
    test "allows requests under the limit" do
      for i <- 1..5 do
        assert :ok == RateLimiter.check_rate({:test, "key_#{i}"}, 5, 900),
               "attempt #{i} should be allowed"
      end
    end

    test "allows exactly max_attempts requests" do
      for _ <- 1..5 do
        assert :ok == RateLimiter.check_rate({:test, "same_key"}, 5, 900)
      end
    end

    test "blocks requests exceeding the limit" do
      for _ <- 1..5 do
        assert :ok == RateLimiter.check_rate({:test, "limited"}, 5, 900)
      end

      assert {:error, :rate_limited} == RateLimiter.check_rate({:test, "limited"}, 5, 900)
    end

    test "tracks different keys independently" do
      for _ <- 1..5 do
        RateLimiter.check_rate({:test, "key_a"}, 5, 900)
      end

      assert {:error, :rate_limited} == RateLimiter.check_rate({:test, "key_a"}, 5, 900)
      assert :ok == RateLimiter.check_rate({:test, "key_b"}, 5, 900)
    end

    test "reset clears all entries" do
      for _ <- 1..5 do
        RateLimiter.check_rate({:test, "reset_key"}, 5, 900)
      end

      assert {:error, :rate_limited} == RateLimiter.check_rate({:test, "reset_key"}, 5, 900)

      RateLimiter.reset()

      assert :ok == RateLimiter.check_rate({:test, "reset_key"}, 5, 900)
    end
  end
end
