class Memory::SearchesController < ApplicationController
  before_action :require_admin

  def create
    @query   = params[:query].to_s
    @results = MemoryFile.matching(@query)
    render :results
  end
end
