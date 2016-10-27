module TestProfiler
  module Witness
    def self.create_witnesses
      to_do = ActiveRecord::Base.descendants.reject { |m| m.name == 'Carto::Organization' }
      (1..10).each do
        Carto::Organization.delete_all rescue nil
        to_do.each { |x| x.delete_all rescue nil }
      end

      ActiveRecord::Base.connection.execute("INSERT INTO organizations (id, name, quota_in_bytes, seats) VALUES ('#{TEST_UUID}', 'witness-org', 0, 0)")
      while to_do.present?
        model = to_do.pop
        to_do.prepend(model) unless create_witness(model)
      end
    end

    def self.assert_witnesses_alive
      ActiveRecord::Base.descendants.each { |model| model.count.should > 0 }
    end

    def self.create_witness(model)
      attributes = model.columns.reject { |c| c.null }.map { |col|
        [col.name.to_sym, value_for(col.sql_type, model.serialized_attributes.include?(col.name))]
      }.to_h
      begin
        instance = model.send(:new)
        instance.stubs(:notify_map_change)
        instance.stubs(:update_named_map)
        instance.stubs(:update_map_dataset_dependencies)
        attributes.each do |k, v|
          instance.send(k.to_s + '=', v)
        end
        instance.save(validate: false)
        true
      rescue ActiveRecord::InvalidForeignKey
        return false
      end
    end

    TEST_UUID = '00000000-0000-0000-0000-000000000000'.freeze
    def self.value_for(type, serialized)
      return {} if serialized
      case type
      when 'uuid'
        TEST_UUID
      when 'json'
        '{}'
      when 'text'
        'text'
      when 'character varying[]'
        ['text']
      when 'integer'
        0
      when 'bigint'
        0
      when 'timestamp with time zone'
        DateTime.now
      when 'timestamp without time zone'
        DateTime.now
      when 'boolean'
        false
      else
        raise 'Unknown type ' + type
      end
    end
  end
end