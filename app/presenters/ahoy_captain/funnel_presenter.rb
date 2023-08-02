module AhoyCaptain
  # this is incredibly naive and needs some tlc
  class FunnelPresenter

    attr_reader :steps
    def initialize(funnel, event_query)
      @funnel = funnel
      @event_query = event_query.joins(:visit)
    end

    def build
      if AhoyCaptain.config.goals.none?
        @goals = []
        return self
      end

      queries = {
        totals: @event_query.select("count(distinct(#{AhoyCaptain.event.table_name}.visit_id)) as unique_visits, '_internal_total_visits_' as name, count(distinct #{AhoyCaptain.event.table_name}.id) as total_events, 0 as sort_order")
      }
      selects = ["SELECT unique_visits, name, total_events, sort_order from totals"]
      last_goal = nil
      map = {}.with_indifferent_access

      AhoyCaptain.config.goals.each_with_index do |goal, index|
        queries[goal.id] = @event_query.select("count(distinct(#{AhoyCaptain.event.table_name}.visit_id)) as unique_visits, '#{goal.id}' as name, count(distinct #{AhoyCaptain.event.table_name}.id) as total_events, #{index + 1} as sort_order").merge(goal.event_query.call).group("#{AhoyCaptain.event.table_name}.name")
        selects << ["SELECT unique_visits, name, total_events, sort_order from #{goal.id}"]
        map[goal.id] = goal
        last_goal = goal
      end

      # activerecord quirk / with bug
      select = selects.join(" UNION ").delete_suffix(" from #{last_goal.id}")
      select = select.delete_prefix("SELECT ")
      steps = ::Ahoy::Event.with(
        queries,
        ).select(select).from("#{last_goal.id}").order("sort_order asc")

      items = ::Ahoy::Event.with(steps: steps).select("total_events, unique_visits, name, round((total_events::numeric/lag(total_events, 1) over ()),2) as drop_off").from("steps").order("sort_order asc").index_by(&:name)
      items.delete("_internal_total_visits_")
      @steps = []

      items.values.each do |item|
        if map[item.name]
          item.name = map[item.name].title
        end
      end

      @steps = items.values
      self
    end


    def total
      @event_query.distinct(:visitor_token).count
    end

    def as_json
      {
        steps: @steps.as_json,
        total: total
      }
    end

    def to_json
      as_json.to_json
    end
  end
end
