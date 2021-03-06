var Backbone = require('backbone');
var cdb = require('cartodb.js');
var DataObservatoryColumnName = require('../../../../../javascripts/cartodb3/data/data-observatory/column-name');
var AnalysisDefinitionNodeModel = require('../../../../../javascripts/cartodb3/data/analysis-definition-node-model');

describe('data/data-observatory/column-name', function () {
  var sqlExecuteBackup = cdb.SQL.prototype.execute;

  beforeEach(function () {
    var configModel = new Backbone.Model({
      base_url: '/u/foo',
      user_name: 'foo',
      sql_api_template: 'foo',
      api_key: 'foo'
    });

    this.nodeDefModel = new AnalysisDefinitionNodeModel({
      id: 'a1',
      type: 'data-observatory-multiple-measures',
      final_column: 'foo',
      source: 'a0'
    }, {
      configModel: configModel,
      collection: new Backbone.Collection()
    });

    this.querySchemaModel = new Backbone.Model({
      query: 'select * from wadus'
    });

    this.nodeDefModel.querySchemaModel = this.querySchemaModel;

    cdb.SQL.prototype.execute = function (query, vars, params) {
      params && params.success({
        rows: [
          {
            obs_getmeta: [{
              suggested_name: 'commuters_16_over_per_sq_km_2010_2014'
            }]
          }
        ]
      });
    };

    this.columnName = new DataObservatoryColumnName({
      configModel: configModel,
      nodeDefModel: this.nodeDefModel
    });

    this.successCallback = jasmine.createSpy('successCallback');
  });

  afterEach(function () {
    cdb.SQL.prototype.execute = sqlExecuteBackup;
  });

  it('initial fetch state', function () {
    expect(this.columnName.isFetching).toBe(false);
  });

  describe('fetch', function () {
    it('fetch without numer_id', function () {
      this.columnName.fetch({
        success: this.successCallback
      });

      expect(this.successCallback).not.toHaveBeenCalled();
    });

    it('fetch with numer_id', function () {
      this.columnName.fetch({
        numer_id: 1,
        success: this.successCallback
      });

      expect(this.successCallback).toHaveBeenCalledWith({
        rows: [
          {
            obs_getmeta: [{
              suggested_name: 'commuters_16_over_per_sq_km_2010_2014'
            }]
          }
        ]
      });
    });
  });

  it('buildQueryOptions', function () {
    var options = this.columnName.buildQueryOptions({
      key: 'foo'
    });

    expect(options).toEqual(jasmine.objectContaining({
      metadata: "'[" + JSON.stringify({key: 'foo'}) + "]'",
      query: 'select * from wadus'
    }));
  });
});
