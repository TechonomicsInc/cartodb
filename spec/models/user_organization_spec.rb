require_relative '../spec_helper'

describe UserOrganization do

  describe 'promoting a user to owner' do
    include_context 'visualization creation helpers'

    before(:each) do
      ::User.any_instance.stubs(:create_in_central).returns(true)
      ::User.any_instance.stubs(:update_in_central).returns(true)
      @organization = Organization.new(quota_in_bytes: 1234567890, name: 'wadus', seats: 5).save

      @owner = create_user(:quota_in_bytes => 524288000, :table_quota => 500)
    end

    after(:each) do
      stub_named_maps_calls
      @organization.destroy_cascade if @organization
      @owner = ::User.where(id: @owner.id).first
      @owner.destroy if @owner
    end

    # See #3534: Quota trigger re-creation not done correctly when promoting user to org
    it 'recreates existing tables triggers' do
      table = create_random_table(@owner)
      id = table.id
      table.insert_row!({})
      table.rows_counted.should == 1

      owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
      owner_org.promote_user_to_admin
      @owner.reload

      table = UserTable.where(id: id).first.service
      table.insert_row!({})
      table.rows_counted.should == 2
    end

    # See #6295: Moving user to its own schema (i.e on org creation) leaves triggers on public schema
    it 'moves triggers to the new schema' do
      table = create_random_table(@owner)

      truncate_table_function_creation = %Q{
        create function truncate_table() returns trigger as $truncate_table$
        begin
          delete from #{table.qualified_table_name};
          return NEW;
        end;
      $truncate_table$ language plpgsql;
      }

      trigger_name = 'testing_trigger'
      @owner.in_database.run(truncate_table_function_creation)
      @owner.in_database.run("create trigger #{trigger_name} after insert on #{table.qualified_table_name} execute procedure truncate_table();")

      new_row = {}
      table.insert_row!(new_row)
      table.actual_row_count.should == 0

      triggers_before = @owner.db_service.triggers_in_user_schema
      triggers_before.map(&:trigger_name).should include(trigger_name)

      owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
      owner_org.promote_user_to_admin
      @owner.reload

      triggers_after = @owner.db_service.triggers_in_user_schema
      triggers_after.map { |t| [t.database_name, t.table_name, t.trigger_name] } .should == triggers_before.map { |t| [t.database_name, t.table_name, t.trigger_name] }

      @owner.db_service.triggers_in_schema('public').should be_empty
    end
  end

  # See #5477 Error assigning as owner a user with non-cartodbfied tables
  it 'can assign an owner user having non-cartodbfied tables' do
    ::User.any_instance.stubs(:create_in_central).returns(true)
    ::User.any_instance.stubs(:update_in_central).returns(true)
    @organization = Organization.new(quota_in_bytes: 1234567890, name: 'non-cartodbfied-org', seats: 5).save
    @owner = create_user(quota_in_bytes: 524288000, table_quota: 500)
    @owner.in_database.run('create table no_cartodbfied_table (test integer)')

    @owner.real_tables.count.should == 1

    owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
    owner_org.promote_user_to_admin
    @owner.reload

    @owner.real_tables.count.should == 1

    @owner.database_schema.should == @owner.username
  end

  it 'keeps tables and metadata if table movement fails' do
    ::User.any_instance.stubs(:create_in_central).returns(true)
    ::User.any_instance.stubs(:update_in_central).returns(true)

    # This is coupled to DBService#move_tables_to_schema implementation, but we need a way to simulate a failure
    Carto::UserTable.stubs(:find_by_user_id_and_name).raises(StandardError.new("Simulation of table movement failure"))

    @organization = Organization.new(quota_in_bytes: 1234567890, name: 'org-that-will-fail', seats: 5).save
    @owner = create_user(quota_in_bytes: 524288000, table_quota: 500)
    @owner.in_database.run('create table no_cartodbfied_table (test integer)')

    # Checks that should also be met afterwards
    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false

    # Promote
    owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
    expect { owner_org.promote_user_to_admin }.to raise_error StandardError
    @owner.reload

    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false
  end

  it 'keeps tables and metadata if rebuild_quota_trigger fails' do
    ::User.any_instance.stubs(:create_in_central).returns(true)
    ::User.any_instance.stubs(:update_in_central).returns(true)

    @organization = Organization.new(quota_in_bytes: 1234567890, name: 'org-that-will-fail-2', seats: 5).save
    @owner = create_user(quota_in_bytes: 524288000, table_quota: 500)
    @owner.in_database.run('create table no_cartodbfied_table (test integer)')

    # Checks that should also be met afterwards
    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false

    CartoDB::UserModule::DBService.any_instance.stubs(:rebuild_quota_trigger).raises(StandardError.new("Failure simulation"))

    # Promote
    owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
    expect { owner_org.promote_user_to_admin }.to raise_error StandardError
    @owner.reload

    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false
  end

  # Currently, an existing, active organization is the only cause
  # that might match #6202 sympthoms, but this is a guess.
  it 'keeps tables and metadata if organization is already active' do
    ::User.any_instance.stubs(:create_in_central).returns(true)
    ::User.any_instance.stubs(:update_in_central).returns(true)

    @owner = create_user(quota_in_bytes: 524288000, table_quota: 500)
    @organization = Organization.new(quota_in_bytes: 1234567890, name: 'org-that-will-fail-3', seats: 5, owner_id: @owner.id).save

    @owner.in_database.run('create table no_cartodbfied_table (test integer)')

    # Checks that should also be met afterwards
    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false

    # Promote
    owner_org = CartoDB::UserOrganization.new(@organization.id, @owner.id)
    expect { owner_org.promote_user_to_admin }.to raise_error StandardError
    @owner.reload

    @owner.database_schema.should == 'public'
    @owner.real_tables.count.should == 1

    @owner.db_service.schema_exists?(@owner.username).should == false
  end
end
